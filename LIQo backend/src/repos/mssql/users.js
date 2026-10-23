import { query, sql } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';

const COLUMNS =
  'id, email, password_hash, full_name, role, is_active, must_change_password, last_login_at, created_by, created_at, updated_at, failed_logins, locked_until, reports_to';
const U_COLUMNS = COLUMNS.split(', ').map((c) => `u.${c}`).join(', ');

export const LOCK_MINUTES = 15;

export async function findByEmail(email) {
  const r = await query(`SELECT ${COLUMNS} FROM users WHERE email = @email`, { email });
  return r.recordset[0] || null;
}

export async function findById(id) {
  const r = await query(
    `SELECT ${U_COLUMNS}, rt.full_name AS reports_to_name FROM users u LEFT JOIN users rt ON rt.id = u.reports_to WHERE u.id = @id`,
    { id: { type: sql.Int, value: id } },
  );
  return r.recordset[0] || null;
}

export async function updateLastLogin(id) {
  await query('UPDATE users SET last_login_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
  });
}

export async function setPassword(id, passwordHash, { mustChange = false } = {}) {
  // A new password always clears a lockout, so an admin reset is the way to unlock early.
  await query(
    `UPDATE users
       SET password_hash = @h, must_change_password = @m, failed_logins = 0, locked_until = NULL, updated_at = SYSDATETIME()
     WHERE id = @id`,
    {
      id: { type: sql.Int, value: id },
      h: passwordHash,
      m: { type: sql.Bit, value: mustChange },
    },
  );
}

/** Counts a failed attempt; locks the account when the limit is reached. Returns { locked, lockedUntil }. */
export async function recordFailedLogin(id, maxAttempts) {
  const r = await query(
    `UPDATE users
        SET locked_until = CASE WHEN failed_logins + 1 >= @max THEN DATEADD(minute, ${LOCK_MINUTES}, SYSDATETIME()) ELSE locked_until END,
            failed_logins = CASE WHEN failed_logins + 1 >= @max THEN 0 ELSE failed_logins + 1 END
      OUTPUT inserted.locked_until
      WHERE id = @id`,
    { id: { type: sql.Int, value: id }, max: { type: sql.Int, value: maxAttempts } },
  );
  const until = r.recordset[0]?.locked_until ?? null;
  return { locked: until != null && new Date(until) > new Date(), lockedUntil: until };
}

export async function clearFailedLogins(id) {
  await query('UPDATE users SET failed_logins = 0, locked_until = NULL WHERE id = @id', { id: { type: sql.Int, value: id } });
}

export async function create({ email, passwordHash, fullName, role, createdBy = null, mustChange = true }) {
  const r = await query(
    `INSERT INTO users (email, password_hash, full_name, role, must_change_password, created_by)
     OUTPUT inserted.id
     VALUES (@email, @h, @name, @role, @m, @createdBy)`,
    {
      email,
      h: passwordHash,
      name: fullName,
      role,
      m: { type: sql.Bit, value: mustChange },
      createdBy: createdBy === null ? null : { type: sql.Int, value: createdBy },
    },
  );
  return r.recordset[0].id;
}

export async function updateProfile(id, { fullName, email }) {
  await query(
    `UPDATE users SET full_name = @name, email = @email, updated_at = SYSDATETIME() WHERE id = @id`,
    { id: { type: sql.Int, value: id }, name: fullName, email },
  );
  return findById(id);
}

/**
 * Deactivates an account. A superadmin is only deactivated while at least one
 * other superadmin stays active; the check and the update are one statement,
 * so two superadmins cannot deactivate each other at the same moment.
 * Returns the updated user, or null when it was refused.
 */
export async function deactivateKeepingASuperadmin(id) {
  const r = await query(
    `UPDATE users SET is_active = 0, updated_at = SYSDATETIME()
      OUTPUT inserted.id
      WHERE id = @id AND (role <> 'superadmin'
        OR (SELECT COUNT(*) FROM users o WHERE o.role = 'superadmin' AND o.is_active = 1 AND o.id <> @id) >= 1)`,
    { id: { type: sql.Int, value: id } },
  );
  return r.recordset[0] ? findById(id) : null;
}

export async function setActive(id, active) {
  await query(`UPDATE users SET is_active = @a, updated_at = SYSDATETIME() WHERE id = @id`, {
    id: { type: sql.Int, value: id },
    a: { type: sql.Bit, value: active },
  });
  return findById(id);
}

/**
 * Paged list. `onlyUserIds` limits the rows to a scope (e.g. mall admins a
 * supervisor may see); null means no limit.
 */
export async function list({ search, role, status, offset, pageSize, sortColumn, sortOrder, onlyUserIds = null, roles = null, unassignedOnly = false, noOwnerOnly = false, reportsTo = null }) {
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (search) {
    where.push('(u.email LIKE @search OR u.full_name LIKE @search)');
    params.search = `%${search}%`;
  }
  if (role) {
    where.push('u.role = @role');
    params.role = role;
  }
  if (roles && roles.length) {
    where.push(`u.role IN (${roles.map((_, i) => `@r${i}`).join(',')})`);
    roles.forEach((r, i) => {
      params[`r${i}`] = r;
    });
  }
  if (status === 'active') where.push('u.is_active = 1');
  if (status === 'inactive') where.push('u.is_active = 0');
  if (unassignedOnly) {
    where.push(`u.role IN ('supervisor','mall_admin') AND NOT EXISTS (SELECT 1 FROM supervisor_assignments sa WHERE sa.user_id = u.id)
      AND NOT EXISTS (SELECT 1 FROM mall_admin_assignments ma WHERE ma.user_id = u.id)`);
  }
  if (noOwnerOnly) where.push(`u.role = 'mall_admin' AND u.reports_to IS NULL`);
  if (reportsTo != null) {
    where.push('u.reports_to = @reportsTo');
    params.reportsTo = { type: sql.Int, value: reportsTo };
  }
  if (onlyUserIds) {
    const { clause, params: p } = inList('u.id', onlyUserIds, 's');
    where.push(clause);
    Object.assign(params, p);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = (await query(`SELECT COUNT(*) AS n FROM users u ${whereSql}`, params)).recordset[0].n;
  const rows = (
    await query(
      `SELECT u.id, u.email, u.full_name, u.role, u.is_active, u.must_change_password, u.last_login_at, u.created_at,
              u.reports_to, rt.full_name AS reports_to_name,
              (SELECT COUNT(*) FROM supervisor_assignments sa WHERE sa.user_id = u.id AND sa.mall_id IS NOT NULL) AS mall_assignments,
              (SELECT COUNT(*) FROM supervisor_assignments sa WHERE sa.user_id = u.id AND sa.branch_id IS NOT NULL)
            + (SELECT COUNT(*) FROM mall_admin_assignments ma WHERE ma.user_id = u.id) AS branch_assignments,
              (SELECT COUNT(*) FROM store_owner_assignments soa WHERE soa.user_id = u.id) AS store_assignments
         FROM users u LEFT JOIN users rt ON rt.id = u.reports_to ${whereSql}
        ORDER BY ${sortColumn} ${sortOrder}
       OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
      params,
    )
  ).recordset;
  return { items: rows.map(toPublic), totalCount: total };
}

/**
 * Assignment counts for list rows: whole malls (supervisors), branches
 * (supervisors and mall admins) and stores (owners). Absent on single reads.
 */
function accessOf(user) {
  if (user.mall_assignments === undefined) return {};
  const access = {
    malls: user.mall_assignments ?? 0,
    branches: user.branch_assignments ?? 0,
    stores: user.store_assignments ?? 0,
  };
  return { access, assignmentCount: access.malls + access.branches + access.stores };
}

/** Public shape sent to the frontend (never the hash). */
export function toPublic(user) {
  if (!user) return null;
  return {
    id: user.id,
    email: user.email,
    fullName: user.full_name,
    role: user.role,
    isActive: !!user.is_active,
    mustChangePassword: !!user.must_change_password,
    lastLoginAt: user.last_login_at,
    createdAt: user.created_at,
    ...accessOf(user),
    reportsTo: user.reports_to == null ? null : { id: user.reports_to, name: user.reports_to_name ?? null },
    lockedUntil: user.locked_until && new Date(user.locked_until) > new Date() ? user.locked_until : null,
  };
}

/**
 * Accounts with the same full name (case and outer spaces ignored), newest
 * first, at most [limit]. `total` is the full count. Names may repeat; the
 * create wizard only warns (owner decision 2026-10-22).
 */
export async function findByFullName(fullName, limit = 3) {
  const r = await query(
    `SELECT TOP (@limit) id, full_name, role, is_active, COUNT(*) OVER () AS total
       FROM users
      WHERE LOWER(LTRIM(RTRIM(full_name))) = LOWER(@name)
      ORDER BY created_at DESC`,
    { name: fullName.trim(), limit: { type: sql.Int, value: limit } },
  );
  return {
    total: r.recordset[0]?.total ?? 0,
    items: r.recordset.map((x) => ({ id: x.id, fullName: x.full_name, role: x.role, isActive: !!x.is_active })),
  };
}
