// Stores and their map spaces on Firestore (P1-06A); documents mirror the SQL rows.
//   stores/<id>, store_spaces/<storeId>_<spaceKey>, _unique/store_name:<branch>:<name>
import { col, docOf, getDb, runTx, nextId, one, all, uniqueRef, Timestamp } from '../../db/firestore.js';
import { parseHours, hoursText } from '../../utils/hours.js';
import { listInMemory, inScope, byId, compare, dupError, fkError } from './util.js';

export function toPublic(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    branchName: row.branch_name,
    mallName: row.mall_name,
    name: row.name,
    categoryId: row.category_id,
    categoryName: row.category_name,
    logoUrl: row.logo_url,
    description: row.description,
    openingHours: row.opening_hours,
    hours: parseHours(row.hours_json),
    status: row.status ?? 'open',
    contactPhone: row.contact_phone,
    contactEmail: row.contact_email,
    isActive: !!row.is_active,
    spaceCount: row.space_count,
    ownerCount: row.owner_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const SORT = { 'b.name': 'branch_name', 'c.name': 'category_name' };

async function joined(rows) {
  const [branches, malls, options, spaces, owners] = await Promise.all([all(col('branches')), all(col('malls')), all(col('branch_options')), all(col('store_spaces')), all(col('store_owner_assignments'))]);
  const b = byId(branches);
  const m = byId(malls);
  const o = byId(options);
  const count = (list, key) => {
    const c = new Map();
    for (const x of list) c.set(x[key], (c.get(x[key]) ?? 0) + 1);
    return c;
  };
  const sc = count(spaces, 'store_id');
  const oc = count(owners, 'store_id');
  return rows.map((s) => {
    const br = b.get(s.branch_id);
    return {
      ...s,
      branch_name: br?.name ?? null,
      mall_name: br ? m.get(br.mall_id)?.name ?? null : null,
      category_name: s.category_id != null ? o.get(s.category_id)?.name ?? null : null,
      space_count: sc.get(s.id) ?? 0,
      owner_count: oc.get(s.id) ?? 0,
    };
  });
}

export async function list({ search, status, branchId, offset, pageSize, sortColumn, sortOrder, scopeBranchIds, onlyStoreIds }) {
  const rows = (await joined(await all(col('stores'))))
    .filter((s) => status !== 'active' || s.is_active)
    .filter((s) => status !== 'inactive' || !s.is_active)
    .filter((s) => !branchId || s.branch_id === Number(branchId))
    .filter((s) => inScope(scopeBranchIds, s.branch_id))
    .filter((s) => inScope(onlyStoreIds, s.id));
  const { items, totalCount } = listInMemory(rows, { search, searchFields: ['name', 'branch_name', 'category_name'], sortColumn, sortOrder, offset, pageSize, sortMap: SORT });
  return { items: items.map(toPublic), totalCount };
}

export async function findById(id) {
  const s = await one('stores', Number(id));
  return s ? toPublic((await joined([s]))[0]) : null;
}

const fieldsOf = (f) => ({
  name: f.name,
  category_id: f.categoryId == null ? null : Number(f.categoryId),
  logo_url: f.logoUrl ?? null,
  description: f.description ?? null,
  opening_hours: f.openingHours ?? null,
  contact_phone: f.contactPhone ?? null,
  contact_email: f.contactEmail ?? null,
});

async function checkCategory(tx, categoryId) {
  if (categoryId == null) return;
  if (!(await tx.get(docOf('branch_options', categoryId))).exists) throw fkError();
}

export async function create(fields, createdBy) {
  const id = await runTx(async (tx) => {
    if (!(await tx.get(docOf('branches', fields.branchId))).exists) throw fkError();
    await checkCategory(tx, fields.categoryId);
    // One store name per branch (SQL: UNIQUE (branch_id, name)).
    const guard = uniqueRef('store_name', `${Number(fields.branchId)}:${fields.name.trim()}`);
    if ((await tx.get(guard)).exists) throw dupError();
    const nid = await nextId('stores', tx);
    tx.set(guard, { id: nid });
    tx.set(docOf('stores', nid), { id: nid, branch_id: Number(fields.branchId), ...fieldsOf(fields), is_active: true, created_by: createdBy ?? null, created_at: Timestamp.now(), updated_at: Timestamp.now() });
    return nid;
  });
  return findById(id);
}

export async function update(id, fields) {
  await runTx(async (tx) => {
    const ref = docOf('stores', id);
    const cur = (await tx.get(ref)).data();
    await checkCategory(tx, fields.categoryId);
    if (cur.name.trim().toLowerCase() !== fields.name.trim().toLowerCase()) {
      const guard = uniqueRef('store_name', `${cur.branch_id}:${fields.name.trim()}`);
      if ((await tx.get(guard)).exists) throw dupError();
      tx.delete(uniqueRef('store_name', `${cur.branch_id}:${cur.name.trim()}`));
      tx.set(guard, { id: Number(id) });
    }
    tx.update(ref, { ...fieldsOf(fields), updated_at: Timestamp.now() });
  });
  return findById(id);
}

export async function setActive(id, active) {
  await docOf('stores', id).update({ is_active: !!active, updated_at: Timestamp.now() });
  return findById(id);
}

// ---- Store ↔ space links ----

export async function spacesFor(storeId) {
  return (await all(col('store_spaces').where('store_id', '==', Number(storeId)))).map((x) => x.space_key).sort(compare);
}

export async function setSpaces(storeId, branchId, keys) {
  await runTx(async (tx) => {
    const old = await tx.get(col('store_spaces').where('store_id', '==', Number(storeId)));
    old.docs.forEach((d) => tx.delete(d.ref));
    for (const key of [...new Set(keys)]) {
      tx.set(docOf('store_spaces', `${Number(storeId)}_${key}`), { store_id: Number(storeId), branch_id: Number(branchId), space_key: key, created_at: Timestamp.now() });
    }
  });
  return spacesFor(storeId);
}

/** Active stores of a branch, id and name only (AI name matching). */
export async function namesForBranch(branchId) {
  return (await all(col('stores').where('branch_id', '==', Number(branchId))))
    .filter((s) => s.is_active)
    .sort((a, b) => compare(a.name, b.name))
    .map((x) => ({ id: x.id, name: x.name }));
}

/** All links in a branch: space_key → [{storeId, storeName}] */
export async function spaceLinksForBranch(branchId) {
  const [links, stores] = await Promise.all([all(col('store_spaces').where('branch_id', '==', Number(branchId))), all(col('stores').where('branch_id', '==', Number(branchId)))]);
  const s = byId(stores);
  return links
    .map((x) => ({ spaceKey: x.space_key, storeId: x.store_id, storeName: s.get(x.store_id)?.name ?? null }))
    .sort((a, b) => compare(a.spaceKey, b.spaceKey) || compare(a.storeName, b.storeName));
}

/** The branch of an active store this store owner is assigned to, or null. */
export async function branchOfOwnedActiveStore(userId, storeId) {
  const link = await one('store_owner_assignments', `${Number(userId)}_${Number(storeId)}`);
  if (!link) return null;
  const s = await one('stores', Number(storeId));
  return s?.is_active ? s.branch_id : null;
}

// ---- Round 21: hours and status (mall admin, or the store owner through the narrow route) ----

export async function setHours(id, hours) {
  await docOf('stores', id).update({ hours_json: hoursText(hours), updated_at: Timestamp.now() });
  return findById(id);
}

export async function setStatus(id, status) {
  await docOf('stores', id).update({ status, updated_at: Timestamp.now() });
  return findById(id);
}
