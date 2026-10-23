import { query, sql, withTransaction, txQuery } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';

export async function supervisorAssignments(userId) {
  const r = await query(
    `SELECT sa.id, sa.mall_id, m.name AS mall_name, sa.branch_id, b.name AS branch_name, bm.name AS branch_mall_name
       FROM supervisor_assignments sa
       LEFT JOIN malls m ON m.id = sa.mall_id
       LEFT JOIN branches b ON b.id = sa.branch_id
       LEFT JOIN malls bm ON bm.id = b.mall_id
      WHERE sa.user_id = @uid
      ORDER BY m.name, bm.name, b.name`,
    { uid: { type: sql.Int, value: userId } },
  );
  return {
    malls: r.recordset.filter((x) => x.mall_id != null).map((x) => ({ id: x.mall_id, name: x.mall_name })),
    branches: r.recordset
      .filter((x) => x.branch_id != null)
      .map((x) => ({ id: x.branch_id, name: x.branch_name, mallName: x.branch_mall_name })),
  };
}

/** Replace a supervisor's whole assignment set in one transaction. */
export async function replaceSupervisorAssignments(userId, { mallIds, branchIds }, assignedBy) {
  await withTransaction(async (tx) => {
    await txQuery(tx, 'DELETE FROM supervisor_assignments WHERE user_id = @uid', { uid: { type: sql.Int, value: userId } });
    for (const mallId of mallIds) {
      await txQuery(tx, 'INSERT INTO supervisor_assignments (user_id, mall_id, assigned_by) VALUES (@uid, @mid, @by)', {
        uid: { type: sql.Int, value: userId },
        mid: { type: sql.Int, value: mallId },
        by: { type: sql.Int, value: assignedBy },
      });
    }
    for (const branchId of branchIds) {
      await txQuery(tx, 'INSERT INTO supervisor_assignments (user_id, branch_id, assigned_by) VALUES (@uid, @bid, @by)', {
        uid: { type: sql.Int, value: userId },
        bid: { type: sql.Int, value: branchId },
        by: { type: sql.Int, value: assignedBy },
      });
    }
  });
  return supervisorAssignments(userId);
}

/** Branch ids of one mall. */
async function branchIdsOfMall(mallId) {
  const r = await query('SELECT id FROM branches WHERE mall_id = @m', { m: { type: sql.Int, value: mallId } });
  return r.recordset.map((x) => x.id);
}

/**
 * Applies the "reports to" rule to every mall admin (see utils/ownership.js):
 * own branch's owner, else the mall's whole-mall owner, first linked, active
 * owners only, else none. Returns the admins whose superior changed.
 */
export async function recomputeReportsTo() {
  const r = await query(`UPDATE u SET reports_to = rt.owner_id, updated_at = SYSDATETIME()
  OUTPUT inserted.id AS id, deleted.reports_to AS from_id, inserted.reports_to AS to_id
  FROM users u
  OUTER APPLY (
    SELECT TOP 1 x.owner_id FROM (
      -- The owner of the admin's own branch first...
      SELECT sa.user_id AS owner_id, 0 AS pri, sa.assigned_at, sa.id
        FROM mall_admin_assignments ma
        JOIN supervisor_assignments sa ON sa.branch_id = ma.branch_id
        JOIN users o ON o.id = sa.user_id AND o.role = 'supervisor' AND o.is_active = 1
       WHERE ma.user_id = u.id
      UNION ALL
      -- ...otherwise the mall's whole-mall owner.
      SELECT sa.user_id, 1, sa.assigned_at, sa.id
        FROM mall_admin_assignments ma
        JOIN branches b ON b.id = ma.branch_id
        JOIN supervisor_assignments sa ON sa.mall_id = b.mall_id
        JOIN users o ON o.id = sa.user_id AND o.role = 'supervisor' AND o.is_active = 1
       WHERE ma.user_id = u.id
    ) x
    ORDER BY x.pri, x.assigned_at, x.id
  ) rt
  WHERE u.role = 'mall_admin' AND ISNULL(u.reports_to, -1) <> ISNULL(rt.owner_id, -1)`);
  return r.recordset.map((x) => ({ id: x.id, from: x.from_id ?? null, to: x.to_id ?? null }));
}

/** Everyone working on one mall: owners (whole-mall or branch-level) and admins with their branches here. */
export async function mallPeople(mallId) {
  const m = { type: sql.Int, value: mallId };
  const owners = (
    await query(
      `SELECT u.id, u.full_name, u.email, u.is_active,
              MAX(CASE WHEN sa.mall_id = @m THEN 1 ELSE 0 END) AS whole_mall,
              STUFF((SELECT ', ' + b.name FROM supervisor_assignments s2 JOIN branches b ON b.id = s2.branch_id
                      WHERE s2.user_id = u.id AND b.mall_id = @m FOR XML PATH('')), 1, 2, '') AS branch_names
         FROM users u JOIN supervisor_assignments sa ON sa.user_id = u.id
         LEFT JOIN branches sb ON sb.id = sa.branch_id
        WHERE sa.mall_id = @m OR sb.mall_id = @m
        GROUP BY u.id, u.full_name, u.email, u.is_active
        ORDER BY whole_mall DESC, u.full_name`,
      { m },
    )
  ).recordset.map((x) => ({
    id: x.id,
    fullName: x.full_name,
    email: x.email,
    isActive: !!x.is_active,
    wholeMall: x.whole_mall === 1,
    branchNames: x.branch_names ?? '',
  }));
  const admins = (
    await query(
      `SELECT u.id, u.full_name, u.email, u.is_active, u.must_change_password, u.reports_to, rt.full_name AS reports_to_name,
              b.id AS branch_id, b.name AS branch_name
         FROM users u JOIN mall_admin_assignments ma ON ma.user_id = u.id
         JOIN branches b ON b.id = ma.branch_id
         LEFT JOIN users rt ON rt.id = u.reports_to
        WHERE b.mall_id = @m
        ORDER BY u.full_name, b.name`,
      { m },
    )
  ).recordset;
  const byAdmin = new Map();
  for (const x of admins) {
    const a = byAdmin.get(x.id) ?? {
      id: x.id,
      fullName: x.full_name,
      email: x.email,
      isActive: !!x.is_active,
      mustChangePassword: !!x.must_change_password,
      reportsTo: x.reports_to == null ? null : { id: x.reports_to, name: x.reports_to_name },
      branches: [],
    };
    a.branches.push({ id: x.branch_id, name: x.branch_name });
    byAdmin.set(x.id, a);
  }
  return { owners, admins: [...byAdmin.values()] };
}

/** Whole-mall ownership for an existing owner account. */
export async function addMallOwner(mallId, userId, assignedBy) {
  await query(
    `IF NOT EXISTS (SELECT 1 FROM supervisor_assignments WHERE user_id = @u AND mall_id = @m)
       INSERT INTO supervisor_assignments (user_id, mall_id, assigned_by) VALUES (@u, @m, @by)`,
    { u: { type: sql.Int, value: userId }, m: { type: sql.Int, value: mallId }, by: { type: sql.Int, value: assignedBy } },
  );
}

/** Removes this mall (whole-mall row and single branches of it) from an owner. The caller re-applies the reports-to rule. */
export async function removeMallOwner(mallId, userId) {
  await query(
    `DELETE sa FROM supervisor_assignments sa LEFT JOIN branches b ON b.id = sa.branch_id
      WHERE sa.user_id = @u AND (sa.mall_id = @m OR b.mall_id = @m)`,
    { u: { type: sql.Int, value: userId }, m: { type: sql.Int, value: mallId } },
  );
}

/** Replaces an admin's branches inside one mall only; branches of other malls are kept. */
export async function setMallAdminBranches(mallId, adminId, branchIds, assignedBy) {
  const mallBranches = await branchIdsOfMall(mallId);
  const outside = branchIds.filter((id) => !mallBranches.includes(id));
  if (outside.length) throw new Error('BRANCH_NOT_IN_MALL');
  const current = await mallAdminAssignments(adminId);
  const keep = current.branches.map((b) => b.id).filter((id) => !mallBranches.includes(id));
  if (keep.length && branchIds.length) throw new Error('ALREADY_ELSEWHERE');
  return replaceMallAdminAssignments(adminId, { branchIds: [...new Set([...keep, ...branchIds])] }, assignedBy);
}

/** Drops this mall's branches from an admin. The caller re-applies the reports-to rule. */
export async function removeMallAdmin(mallId, adminId, assignedBy) {
  return setMallAdminBranches(mallId, adminId, [], assignedBy);
}

export async function mallAdminAssignments(userId) {
  const r = await query(
    `SELECT ma.branch_id, b.name AS branch_name, m.id AS mall_id, m.name AS mall_name
       FROM mall_admin_assignments ma
       JOIN branches b ON b.id = ma.branch_id
       JOIN malls m ON m.id = b.mall_id
      WHERE ma.user_id = @uid
      ORDER BY m.name, b.name`,
    { uid: { type: sql.Int, value: userId } },
  );
  return {
    branches: r.recordset.map((x) => ({ id: x.branch_id, name: x.branch_name, mallId: x.mall_id, mallName: x.mall_name })),
  };
}

/** A mall admin manages exactly one branch (owner decision, 2026-10-21). */
export const ONE_BRANCH = 'ONE_BRANCH';

export async function replaceMallAdminAssignments(userId, { branchIds }, assignedBy) {
  if (branchIds.length > 1) throw new Error(ONE_BRANCH);
  await withTransaction(async (tx) => {
    await txQuery(tx, 'DELETE FROM mall_admin_assignments WHERE user_id = @uid', { uid: { type: sql.Int, value: userId } });
    for (const branchId of branchIds) {
      await txQuery(tx, 'INSERT INTO mall_admin_assignments (user_id, branch_id, assigned_by) VALUES (@uid, @bid, @by)', {
        uid: { type: sql.Int, value: userId },
        bid: { type: sql.Int, value: branchId },
        by: { type: sql.Int, value: assignedBy },
      });
    }
  });
  return mallAdminAssignments(userId);
}

/** The mall admins placed on one branch (several are allowed). */
export async function branchAdmins(branchId) {
  const r = await query(
    `SELECT u.id, u.full_name, u.is_active
       FROM mall_admin_assignments ma
       JOIN users u ON u.id = ma.user_id
      WHERE ma.branch_id = @b
      ORDER BY u.full_name`,
    { b: { type: sql.Int, value: branchId } },
  );
  return r.recordset.map((x) => ({ id: x.id, fullName: x.full_name, isActive: !!x.is_active }));
}
