// Resolves what a signed-in user may see. Every scoped list and write uses this.
//
//   superadmin  → everything
//   supervisor  → assigned malls (all their branches) + directly assigned branches
//   mall_admin  → assigned branches
//   store_owner → assigned stores (and, read-only, the branches those stores are in)

import { query, sql } from '../db/pool.js';
import { AppError } from '../middleware/errors.js';

/**
 * [includeInactive] (mall owners only): also return the owner's own inactive
 * malls and branches, so the owner can still see and reactivate what they
 * deactivated (owner decision 2026-10-22). Everything else (stores, analytics,
 * admins, announcements) keeps using the default, active-only scope.
 */
export async function resolveScope(user, { includeInactive = false } = {}) {
  if (user.role === 'superadmin') {
    return { all: true, mallIds: null, branchIds: null, storeIds: null, wholeMallIds: null };
  }

  if (user.role === 'supervisor') {
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
      { uid: { type: sql.Int, value: user.id } },
    );
    const mallIds = new Set();
    const directBranchIds = new Set();
    for (const row of r.recordset) {
      if (row.mall_id != null) mallIds.add(row.mall_id);
      if (row.branch_id != null) directBranchIds.add(row.branch_id);
    }
    // Malls owned whole (not just one of their branches): only these may be changed by the owner.
    const wholeMallIds = [...mallIds];
    let branchIds = [...directBranchIds];
    if (mallIds.size > 0) {
      const { clause, params } = inList('mall_id', [...mallIds], 'm');
      const br = await query(`SELECT id FROM branches WHERE ${clause} ${includeInactive ? '' : 'AND is_active = 1'}`, params);
      branchIds = [...new Set([...branchIds, ...br.recordset.map((x) => x.id)])];
    }
    // Malls visible = assigned malls + malls of directly assigned branches.
    for (const row of r.recordset) if (row.branch_mall_id != null) mallIds.add(row.branch_mall_id);
    return { all: false, mallIds: [...mallIds], branchIds, storeIds: null, wholeMallIds };
  }

  if (user.role === 'mall_admin') {
    const r = await query(
      `SELECT ma.branch_id, b.mall_id FROM mall_admin_assignments ma
         JOIN branches b ON b.id = ma.branch_id
         JOIN malls m ON m.id = b.mall_id
        WHERE ma.user_id = @uid AND b.is_active = 1 AND m.is_active = 1`,
      { uid: { type: sql.Int, value: user.id } },
    );
    return {
      all: false,
      mallIds: [...new Set(r.recordset.map((x) => x.mall_id))],
      branchIds: r.recordset.map((x) => x.branch_id),
      storeIds: null,
    };
  }

  // store_owner
  const r = await query(
    `SELECT soa.store_id, s.branch_id, b.mall_id
       FROM store_owner_assignments soa
       JOIN stores s ON s.id = soa.store_id
       JOIN branches b ON b.id = s.branch_id
       JOIN malls m ON m.id = b.mall_id
      WHERE soa.user_id = @uid AND s.is_active = 1 AND b.is_active = 1 AND m.is_active = 1`,
    { uid: { type: sql.Int, value: user.id } },
  );
  return {
    all: false,
    mallIds: [...new Set(r.recordset.map((x) => x.mall_id))],
    branchIds: [...new Set(r.recordset.map((x) => x.branch_id))],
    storeIds: r.recordset.map((x) => x.store_id),
  };
}

/** Builds "col IN (@p0,@p1,...)" plus the params object. Empty list → "1=0". */
export function inList(column, ids, prefix = 'p') {
  if (!ids || ids.length === 0) return { clause: '1=0', params: {} };
  const names = ids.map((_, i) => `@${prefix}${i}`);
  const params = Object.fromEntries(ids.map((id, i) => [`${prefix}${i}`, { type: sql.Int, value: id }]));
  return { clause: `${column} IN (${names.join(',')})`, params };
}

export function assertBranchInScope(scope, branchId) {
  if (scope.all) return;
  if (!scope.branchIds.includes(Number(branchId))) {
    throw new AppError(403, 'That branch is outside your assigned scope.');
  }
}

/** Changing a mall (name, logo, active state) needs a whole-mall assignment; owning one branch is not enough. */
export function assertWholeMallOwner(scope, mallId) {
  if (scope.all) return;
  if (!scope.wholeMallIds || !scope.wholeMallIds.includes(Number(mallId))) {
    throw new AppError(403, 'Only an owner of the whole mall, or a superadmin, can change this mall.');
  }
}

export function assertMallInScope(scope, mallId) {
  if (scope.all) return;
  if (!scope.mallIds.includes(Number(mallId))) {
    throw new AppError(403, 'That mall is outside your assigned scope.');
  }
}

export function assertStoreInScope(scope, storeId) {
  if (scope.all) return;
  if (!scope.storeIds || !scope.storeIds.includes(Number(storeId))) {
    throw new AppError(403, 'That store is not assigned to you.');
  }
}
