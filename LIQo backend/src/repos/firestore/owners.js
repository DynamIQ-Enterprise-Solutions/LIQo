// Store owners and their stores on Firestore (P1-06A).
//   store_owner_assignments/<userId>_<storeId>  (SQL: UNIQUE (user_id, store_id))
import { col, docOf, all, Timestamp } from '../../db/firestore.js';
import { listInMemory, byId, compare } from './util.js';

/** Store owners whose stores sit in the given branches (null = all). Paged. */
export async function list({ search, status, offset, pageSize, sortColumn, sortOrder, scopeBranchIds }) {
  const [users, soa, stores] = await Promise.all([all(col('users').where('role', '==', 'store_owner')), all(col('store_owner_assignments')), all(col('stores'))]);
  const s = byId(stores);
  const scope = scopeBranchIds ? new Set(scopeBranchIds.map(Number)) : null;
  const rows = users
    .filter((u) => status !== 'active' || u.is_active)
    .filter((u) => status !== 'inactive' || !u.is_active)
    .filter((u) => {
      if (!scope) return true;
      const mine = soa.filter((a) => a.user_id === u.id);
      // Owners of stores in scope, plus owners who currently have no store (so they can be re-assigned).
      return mine.length === 0 || mine.some((a) => scope.has(s.get(a.store_id)?.branch_id));
    });
  const { items, totalCount } = listInMemory(rows, { search, searchFields: ['email', 'full_name'], sortColumn, sortOrder, offset, pageSize });
  const storesByUser = await storesForOwners(items.map((r) => r.id));
  return {
    items: items.map((r) => ({
      id: r.id,
      email: r.email,
      fullName: r.full_name,
      role: 'store_owner',
      isActive: !!r.is_active,
      mustChangePassword: !!r.must_change_password,
      lastLoginAt: r.last_login_at,
      createdAt: r.created_at,
      stores: storesByUser.get(r.id) || [],
    })),
    totalCount,
  };
}

export async function storesForOwners(userIds) {
  const map = new Map();
  if (userIds.length === 0) return map;
  const want = new Set(userIds.map(Number));
  const [soa, stores, branches] = await Promise.all([all(col('store_owner_assignments')), all(col('stores')), all(col('branches'))]);
  const s = byId(stores);
  const b = byId(branches);
  const rows = soa
    .filter((a) => want.has(a.user_id) && s.has(a.store_id))
    .map((a) => {
      const st = s.get(a.store_id);
      return { user_id: a.user_id, id: st.id, name: st.name, branch_id: st.branch_id, branch_name: b.get(st.branch_id)?.name ?? null, is_active: st.is_active };
    })
    .sort((x, y) => compare(x.branch_name, y.branch_name) || compare(x.name, y.name));
  for (const row of rows) {
    if (!map.has(row.user_id)) map.set(row.user_id, []);
    map.get(row.user_id).push({ id: row.id, name: row.name, branchId: row.branch_id, branchName: row.branch_name, isActive: !!row.is_active });
  }
  return map;
}

export async function storesForOwner(userId) {
  return (await storesForOwners([userId])).get(Number(userId)) || [];
}

export async function assign(userId, storeId, assignedBy) {
  const ref = docOf('store_owner_assignments', `${Number(userId)}_${Number(storeId)}`);
  if ((await ref.get()).exists) return;
  await ref.set({ user_id: Number(userId), store_id: Number(storeId), assigned_by: assignedBy ?? null, assigned_at: Timestamp.now() });
}

export async function unassign(userId, storeId) {
  await docOf('store_owner_assignments', `${Number(userId)}_${Number(storeId)}`).delete();
}

export async function ownersForStore(storeId) {
  const [soa, users] = await Promise.all([all(col('store_owner_assignments').where('store_id', '==', Number(storeId))), all(col('users'))]);
  const u = byId(users);
  return soa
    .map((a) => u.get(a.user_id))
    .filter(Boolean)
    .map((x) => ({ id: x.id, email: x.email, fullName: x.full_name, isActive: !!x.is_active }))
    .sort((a, b) => compare(a.fullName, b.fullName));
}
