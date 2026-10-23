// Malls on Firestore (P1-06A); documents mirror the SQL rows.
import { col, docOf, runTx, nextId, one, all, uniqueRef, Timestamp } from '../../db/firestore.js';
import { listInMemory, inScope, dupError } from './util.js';

export function toPublic(row) {
  return {
    id: row.id,
    name: row.name,
    logoUrl: row.logo_url,
    isActive: !!row.is_active,
    branchCount: row.branch_count ?? undefined,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function branchCounts(scopeBranchIds) {
  const branches = await all(col('branches'));
  const m = new Map();
  for (const b of branches) if (inScope(scopeBranchIds, b.id)) m.set(b.mall_id, (m.get(b.mall_id) ?? 0) + 1);
  return m;
}

export async function list({ search, status, offset, pageSize, sortColumn, sortOrder, scopeMallIds, scopeBranchIds = null }) {
  const [malls, counts] = await Promise.all([all(col('malls')), branchCounts(scopeBranchIds)]);
  const rows = malls
    .filter((m) => status !== 'active' || m.is_active)
    .filter((m) => status !== 'inactive' || !m.is_active)
    .filter((m) => inScope(scopeMallIds, m.id))
    .map((m) => ({ ...m, branch_count: counts.get(m.id) ?? 0 }));
  const { items, totalCount } = listInMemory(rows, { search, searchFields: ['name'], sortColumn, sortOrder, offset, pageSize });
  return { items: items.map(toPublic), totalCount };
}

export async function findById(id, { scopeBranchIds = null } = {}) {
  const m = await one('malls', Number(id));
  if (!m) return null;
  const counts = await branchCounts(scopeBranchIds);
  return toPublic({ ...m, branch_count: counts.get(m.id) ?? 0 });
}

export async function create({ name, logoUrl, createdBy }) {
  const id = await runTx(async (tx) => {
    // One mall per name (SQL: UNIQUE).
    const guard = uniqueRef('mall_name', name.trim());
    if ((await tx.get(guard)).exists) throw dupError();
    const nid = await nextId('malls', tx);
    tx.set(guard, { id: nid });
    tx.set(docOf('malls', nid), { id: nid, name, logo_url: logoUrl ?? null, is_active: true, created_by: createdBy ?? null, created_at: Timestamp.now(), updated_at: Timestamp.now() });
    return nid;
  });
  return findById(id);
}

export async function update(id, { name, logoUrl }) {
  await runTx(async (tx) => {
    const ref = docOf('malls', id);
    const cur = (await tx.get(ref)).data();
    if (cur.name.trim().toLowerCase() !== name.trim().toLowerCase()) {
      const guard = uniqueRef('mall_name', name.trim());
      if ((await tx.get(guard)).exists) throw dupError();
      tx.delete(uniqueRef('mall_name', cur.name.trim()));
      tx.set(guard, { id: Number(id) });
    }
    tx.update(ref, { name, logo_url: logoUrl ?? null, updated_at: Timestamp.now() });
  });
  return findById(id);
}

export async function setActive(id, active) {
  await docOf('malls', id).update({ is_active: !!active, updated_at: Timestamp.now() });
  return findById(id);
}

/** What a deactivation would hide: active branches and stores, and the mall's admins. */
export async function impact(id) {
  const [branches, stores, ma] = await Promise.all([all(col('branches').where('mall_id', '==', Number(id))), all(col('stores')), all(col('mall_admin_assignments'))]);
  const branchIds = new Set(branches.map((b) => b.id));
  return {
    branches: branches.filter((b) => b.is_active).length,
    stores: stores.filter((s) => branchIds.has(s.branch_id) && s.is_active).length,
    mallAdmins: new Set(ma.filter((a) => branchIds.has(a.branch_id)).map((a) => a.user_id)).size,
  };
}
