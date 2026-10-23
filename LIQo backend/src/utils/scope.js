// Resolves what a signed-in user may see. Every scoped list and write uses this.
//
//   superadmin  → everything
//   supervisor  → assigned malls (all their branches) + directly assigned branches
//   mall_admin  → assigned branches
//   store_owner → assigned stores (and, read-only, the branches those stores are in)

import * as assigned from '../repos/scope.js';
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
    const rows = await assigned.supervisorAssignments(user.id, includeInactive);
    const mallIds = new Set();
    const directBranchIds = new Set();
    for (const row of rows) {
      if (row.mallId != null) mallIds.add(row.mallId);
      if (row.branchId != null) directBranchIds.add(row.branchId);
    }
    // Malls owned whole (not just one of their branches): only these may be changed by the owner.
    const wholeMallIds = [...mallIds];
    let branchIds = [...directBranchIds];
    if (mallIds.size > 0) branchIds = [...new Set([...branchIds, ...(await assigned.branchIdsOfMalls([...mallIds], includeInactive))])];
    // Malls visible = assigned malls + malls of directly assigned branches.
    for (const row of rows) if (row.branchMallId != null) mallIds.add(row.branchMallId);
    return { all: false, mallIds: [...mallIds], branchIds, storeIds: null, wholeMallIds };
  }

  if (user.role === 'mall_admin') {
    const rows = await assigned.mallAdminBranches(user.id);
    return { all: false, mallIds: [...new Set(rows.map((x) => x.mallId))], branchIds: rows.map((x) => x.branchId), storeIds: null };
  }

  // store_owner
  const rows = await assigned.storeOwnerStores(user.id);
  return {
    all: false,
    mallIds: [...new Set(rows.map((x) => x.mallId))],
    branchIds: [...new Set(rows.map((x) => x.branchId))],
    storeIds: rows.map((x) => x.storeId),
  };
}

// SQL helper kept here for older imports; new code imports it from db/sqlHelpers.js.
export { inList } from '../db/sqlHelpers.js';

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
