// What a signed-in user is assigned to, on Firestore (P1-06A), for utils/scope.js.
import { col, all } from '../../db/firestore.js';
import { byId } from './util.js';

export async function supervisorAssignments(userId, includeInactive) {
  const [rows, malls, branches] = await Promise.all([all(col('supervisor_assignments').where('user_id', '==', Number(userId))), all(col('malls')), all(col('branches'))]);
  const m = byId(malls);
  const b = byId(branches);
  return rows
    .filter((x) => {
      if (includeInactive) return true;
      if (x.mall_id != null && !m.get(x.mall_id)?.is_active) return false;
      if (x.branch_id != null) {
        const br = b.get(x.branch_id);
        if (!br?.is_active || !m.get(br.mall_id)?.is_active) return false;
      }
      return true;
    })
    .map((x) => ({ mallId: x.mall_id ?? null, branchId: x.branch_id ?? null, branchMallId: x.branch_id != null ? b.get(x.branch_id)?.mall_id ?? null : null }));
}

export async function branchIdsOfMalls(mallIds, includeInactive) {
  if (!mallIds.length) return [];
  const want = new Set(mallIds.map(Number));
  return (await all(col('branches'))).filter((x) => want.has(x.mall_id) && (includeInactive || x.is_active)).map((x) => x.id);
}

export async function mallAdminBranches(userId) {
  const [rows, malls, branches] = await Promise.all([all(col('mall_admin_assignments').where('user_id', '==', Number(userId))), all(col('malls')), all(col('branches'))]);
  const m = byId(malls);
  const b = byId(branches);
  return rows
    .map((x) => b.get(x.branch_id))
    .filter((br) => br?.is_active && m.get(br.mall_id)?.is_active)
    .map((br) => ({ branchId: br.id, mallId: br.mall_id }));
}

export async function storeOwnerStores(userId) {
  const [rows, malls, branches, stores] = await Promise.all([all(col('store_owner_assignments').where('user_id', '==', Number(userId))), all(col('malls')), all(col('branches')), all(col('stores'))]);
  const m = byId(malls);
  const b = byId(branches);
  const s = byId(stores);
  const out = [];
  for (const x of rows) {
    const st = s.get(x.store_id);
    const br = st && b.get(st.branch_id);
    if (st?.is_active && br?.is_active && m.get(br.mall_id)?.is_active) out.push({ storeId: st.id, branchId: br.id, mallId: br.mall_id });
  }
  return out;
}
