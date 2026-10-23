// Branches on Firestore (P1-06A); documents mirror the SQL rows (mall_name joined in).
import { col, docOf, runTx, nextId, one, all, uniqueRef, Timestamp } from '../../db/firestore.js';
import { listInMemory, inScope, byId, dupError, fkError } from './util.js';

export function toPublic(row) {
  return {
    id: row.id,
    mallId: row.mall_id,
    mallName: row.mall_name,
    name: row.name,
    logoUrl: row.logo_url,
    address: row.address,
    latitude: row.latitude == null ? null : Number(row.latitude),
    longitude: row.longitude == null ? null : Number(row.longitude),
    openingHours: row.opening_hours,
    contactPhone: row.contact_phone,
    contactEmail: row.contact_email,
    isActive: !!row.is_active,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const SORT = { 'm.name': 'mall_name' };

async function withMall(rows) {
  const malls = byId(await all(col('malls')));
  return rows.map((b) => ({ ...b, mall_name: malls.get(b.mall_id)?.name ?? null }));
}

export async function list({ search, status, mallId, offset, pageSize, sortColumn, sortOrder, scopeBranchIds }) {
  const rows = (await withMall(await all(col('branches'))))
    .filter((b) => status !== 'active' || b.is_active)
    .filter((b) => status !== 'inactive' || !b.is_active)
    .filter((b) => !mallId || b.mall_id === Number(mallId))
    .filter((b) => inScope(scopeBranchIds, b.id));
  const { items, totalCount } = listInMemory(rows, { search, searchFields: ['name', 'mall_name', 'address'], sortColumn, sortOrder, offset, pageSize, sortMap: SORT });
  return { items: items.map(toPublic), totalCount };
}

export async function findById(id) {
  const b = await one('branches', Number(id));
  if (!b) return null;
  const m = await one('malls', b.mall_id);
  return toPublic({ ...b, mall_name: m?.name ?? null });
}

const fieldsOf = (f) => ({
  name: f.name,
  logo_url: f.logoUrl ?? null,
  address: f.address ?? null,
  latitude: f.latitude == null ? null : Number(f.latitude),
  longitude: f.longitude == null ? null : Number(f.longitude),
  opening_hours: f.openingHours ?? null,
  contact_phone: f.contactPhone ?? null,
  contact_email: f.contactEmail ?? null,
});

export async function create(fields, createdBy) {
  const id = await runTx(async (tx) => {
    // A branch belongs to an existing mall (SQL: foreign key).
    const mall = await tx.get(docOf('malls', fields.mallId));
    if (!mall.exists) throw fkError();
    // One branch name per mall (SQL: UNIQUE (mall_id, name)).
    const guard = uniqueRef('branch_name', `${Number(fields.mallId)}:${fields.name.trim()}`);
    if ((await tx.get(guard)).exists) throw dupError();
    const nid = await nextId('branches', tx);
    tx.set(guard, { id: nid });
    tx.set(docOf('branches', nid), { id: nid, mall_id: Number(fields.mallId), ...fieldsOf(fields), is_active: true, created_by: createdBy ?? null, created_at: Timestamp.now(), updated_at: Timestamp.now() });
    return nid;
  });
  return findById(id);
}

export async function update(id, fields) {
  await runTx(async (tx) => {
    const ref = docOf('branches', id);
    const cur = (await tx.get(ref)).data();
    if (fields.name != null && cur.name.trim().toLowerCase() !== fields.name.trim().toLowerCase()) {
      const guard = uniqueRef('branch_name', `${cur.mall_id}:${fields.name.trim()}`);
      if ((await tx.get(guard)).exists) throw dupError();
      tx.delete(uniqueRef('branch_name', `${cur.mall_id}:${cur.name.trim()}`));
      tx.set(guard, { id: Number(id) });
    }
    tx.update(ref, { ...fieldsOf(fields), updated_at: Timestamp.now() });
  });
  return findById(id);
}

/** Edit only the information fields (not the name or mall). Used by supervisors and mall admins. */
export async function updateInfo(id, fields) {
  const current = await findById(id);
  return update(id, { ...current, ...fields, name: current.name });
}

export async function setActive(id, active) {
  await docOf('branches', id).update({ is_active: !!active, updated_at: Timestamp.now() });
  return findById(id);
}

/** What a deactivation would hide: active stores, their owners, and the branch's mall admins. */
export async function impact(id) {
  const bid = Number(id);
  const [stores, soa, ma] = await Promise.all([all(col('stores').where('branch_id', '==', bid)), all(col('store_owner_assignments')), all(col('mall_admin_assignments').where('branch_id', '==', bid))]);
  const storeIds = new Set(stores.map((s) => s.id));
  return {
    stores: stores.filter((s) => s.is_active).length,
    storeOwners: new Set(soa.filter((a) => storeIds.has(a.store_id)).map((a) => a.user_id)).size,
    mallAdmins: ma.length,
  };
}
