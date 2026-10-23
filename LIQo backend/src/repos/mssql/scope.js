// What a signed-in user is assigned to, for utils/scope.js resolveScope() (P1-06A:
// the SQL moved here from the util).
import { query, sql } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';

const int = (v) => ({ type: sql.Int, value: v });

/** A mall owner's assignments: whole malls and single branches (with each branch's mall). */
export async function supervisorAssignments(userId, includeInactive) {
  const activeOnly = includeInactive
    ? ''
    : `AND (sa.mall_id IS NULL OR m.is_active = 1)
        AND (sa.branch_id IS NULL OR (b.is_active = 1 AND bm.is_active = 1))`;
  const r = await query(
    `SELECT sa.mall_id, sa.branch_id, b.mall_id AS branch_mall_id
       FROM supervisor_assignments sa
       LEFT JOIN malls m ON m.id = sa.mall_id
       LEFT JOIN branches b ON b.id = sa.branch_id
       LEFT JOIN malls bm ON bm.id = b.mall_id
      WHERE sa.user_id = @uid ${activeOnly}`,
    { uid: int(userId) },
  );
  return r.recordset.map((x) => ({ mallId: x.mall_id, branchId: x.branch_id, branchMallId: x.branch_mall_id }));
}

/** Branch ids of these malls (active ones only unless asked). */
export async function branchIdsOfMalls(mallIds, includeInactive) {
  if (!mallIds.length) return [];
  const { clause, params } = inList('mall_id', mallIds, 'm');
  const r = await query(`SELECT id FROM branches WHERE ${clause} ${includeInactive ? '' : 'AND is_active = 1'}`, params);
  return r.recordset.map((x) => x.id);
}

/** A mall admin's active branch (and its mall). */
export async function mallAdminBranches(userId) {
  const r = await query(
    `SELECT ma.branch_id, b.mall_id FROM mall_admin_assignments ma
       JOIN branches b ON b.id = ma.branch_id
       JOIN malls m ON m.id = b.mall_id
      WHERE ma.user_id = @uid AND b.is_active = 1 AND m.is_active = 1`,
    { uid: int(userId) },
  );
  return r.recordset.map((x) => ({ branchId: x.branch_id, mallId: x.mall_id }));
}

/** A store owner's active stores (with branch and mall). */
export async function storeOwnerStores(userId) {
  const r = await query(
    `SELECT soa.store_id, s.branch_id, b.mall_id
       FROM store_owner_assignments soa
       JOIN stores s ON s.id = soa.store_id
       JOIN branches b ON b.id = s.branch_id
       JOIN malls m ON m.id = b.mall_id
      WHERE soa.user_id = @uid AND s.is_active = 1 AND b.is_active = 1 AND m.is_active = 1`,
    { uid: int(userId) },
  );
  return r.recordset.map((x) => ({ storeId: x.store_id, branchId: x.branch_id, mallId: x.mall_id }));
}
