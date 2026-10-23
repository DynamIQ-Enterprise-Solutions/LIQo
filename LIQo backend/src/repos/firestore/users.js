// Accounts on Firestore (P1-06A). Documents mirror the SQL row (snake_case
// columns), so routes get the same shapes on both drivers.
//   users/<id>                 the account
//   _unique/email:<email>      one account per email (SQL: UNIQUE)
import { col, docOf, getDb, runTx, nextId, one, all, uniqueRef, fromStore, Timestamp } from '../../db/firestore.js';
import { LOCK_MINUTES } from '../shared/users.js';
import { listInMemory } from './util.js';

export { LOCK_MINUTES };

const now = () => Timestamp.now();

async function withReportsToName(u) {
  if (!u) return null;
  if (u.reports_to == null) return { ...u, reports_to_name: null };
  const rt = await one('users', u.reports_to);
  return { ...u, reports_to_name: rt?.full_name ?? null };
}

export async function findByEmail(email) {
  const rows = await all(col('users').where('email_lc', '==', String(email).toLowerCase()).limit(1));
  return rows[0] || null;
}

export async function findById(id) {
  return withReportsToName(await one('users', Number(id)));
}

export async function updateLastLogin(id) {
  await docOf('users', id).update({ last_login_at: now() });
}

export async function setPassword(id, passwordHash, { mustChange = false } = {}) {
  // A new password always clears a lockout, so an admin reset is the way to unlock early.
  await docOf('users', id).update({ password_hash: passwordHash, must_change_password: mustChange, failed_logins: 0, locked_until: null, updated_at: now() });
}

/** Counts a failed attempt; locks the account when the limit is reached. Returns { locked, lockedUntil }. */
export async function recordFailedLogin(id, maxAttempts) {
  return runTx(async (tx) => {
    const ref = docOf('users', id);
    const u = (await tx.get(ref)).data();
    const n = (u.failed_logins ?? 0) + 1;
    let until = u.locked_until ? u.locked_until.toDate() : null;
    let failed = n;
    if (n >= maxAttempts) {
      until = new Date(Date.now() + LOCK_MINUTES * 60 * 1000);
      failed = 0;
    }
    tx.update(ref, { failed_logins: failed, locked_until: until ? Timestamp.fromDate(until) : null });
    return { locked: until != null && until > new Date(), lockedUntil: until };
  });
}

export async function clearFailedLogins(id) {
  await docOf('users', id).update({ failed_logins: 0, locked_until: null });
}

export async function create({ email, passwordHash, fullName, role, createdBy = null, mustChange = true }) {
  return runTx(async (tx) => {
    const guard = uniqueRef('email', email);
    if ((await tx.get(guard)).exists) {
      const e = new Error('An account with that email already exists.');
      e.number = 2627; // the SQL Server duplicate-key number routes already understand
      throw e;
    }
    const id = await nextId('users', tx);
    tx.set(guard, { userId: id });
    tx.set(docOf('users', id), {
      id,
      email,
      email_lc: String(email).toLowerCase(),
      password_hash: passwordHash,
      full_name: fullName,
      role,
      is_active: true,
      must_change_password: mustChange,
      last_login_at: null,
      created_by: createdBy,
      created_at: now(),
      updated_at: now(),
      failed_logins: 0,
      locked_until: null,
      reports_to: null,
    });
    return id;
  });
}

export async function updateProfile(id, { fullName, email }) {
  await runTx(async (tx) => {
    const ref = docOf('users', id);
    const u = (await tx.get(ref)).data();
    const changed = String(u.email).toLowerCase() !== String(email).toLowerCase();
    if (changed) {
      const guard = uniqueRef('email', email);
      const g = await tx.get(guard);
      if (g.exists && g.data().userId !== Number(id)) {
        const e = new Error('Another account already uses that email.');
        e.number = 2627;
        throw e;
      }
      tx.delete(uniqueRef('email', u.email));
      tx.set(guard, { userId: Number(id) });
    }
    tx.update(ref, { full_name: fullName, email, email_lc: String(email).toLowerCase(), updated_at: now() });
  });
  return findById(id);
}

/**
 * Deactivates an account. A superadmin is only deactivated while at least one
 * other superadmin stays active; the check and the update are one transaction.
 * Returns the updated user, or null when it was refused.
 */
export async function deactivateKeepingASuperadmin(id) {
  const ok = await runTx(async (tx) => {
    const ref = docOf('users', id);
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const u = snap.data();
    if (u.role === 'superadmin') {
      const others = await tx.get(col('users').where('role', '==', 'superadmin').where('is_active', '==', true));
      if (others.docs.filter((d) => d.data().id !== Number(id)).length < 1) return false;
    }
    tx.update(ref, { is_active: false, updated_at: now() });
    return true;
  });
  return ok ? findById(id) : null;
}

export async function setActive(id, active) {
  await docOf('users', id).update({ is_active: !!active, updated_at: now() });
  return findById(id);
}

/** Store, admin and owner assignment counts per user (for list rows). */
async function assignmentCounts() {
  const [sa, ma, soa] = await Promise.all([all(col('supervisor_assignments')), all(col('mall_admin_assignments')), all(col('store_owner_assignments'))]);
  const m = new Map();
  const get = (id) => {
    if (!m.has(id)) m.set(id, { malls: 0, branches: 0, stores: 0, any: false });
    return m.get(id);
  };
  for (const x of sa) {
    const c = get(x.user_id);
    c.any = true;
    if (x.mall_id != null) c.malls++;
    if (x.branch_id != null) c.branches++;
  }
  for (const x of ma) {
    const c = get(x.user_id);
    c.any = true;
    c.branches++;
  }
  for (const x of soa) get(x.user_id).stores++;
  return m;
}

/**
 * Paged list. `onlyUserIds` limits the rows to a scope (e.g. mall admins a
 * supervisor may see); null means no limit.
 */
export async function list({ search, role, status, offset, pageSize, sortColumn, sortOrder, onlyUserIds = null, roles = null, unassignedOnly = false, noOwnerOnly = false, reportsTo = null }) {
  const [users, counts] = await Promise.all([all(col('users')), assignmentCounts()]);
  const byId = new Map(users.map((u) => [u.id, u]));
  const only = onlyUserIds ? new Set(onlyUserIds.map(Number)) : null;
  const rows = users
    .filter((u) => !role || u.role === role)
    .filter((u) => !roles || !roles.length || roles.includes(u.role))
    .filter((u) => status !== 'active' || u.is_active)
    .filter((u) => status !== 'inactive' || !u.is_active)
    .filter((u) => !unassignedOnly || (['supervisor', 'mall_admin'].includes(u.role) && !counts.get(u.id)?.any))
    .filter((u) => !noOwnerOnly || (u.role === 'mall_admin' && u.reports_to == null))
    .filter((u) => reportsTo == null || u.reports_to === Number(reportsTo))
    .filter((u) => !only || only.has(u.id))
    .map((u) => {
      const c = counts.get(u.id) ?? { malls: 0, branches: 0, stores: 0 };
      return { ...u, reports_to_name: u.reports_to == null ? null : byId.get(u.reports_to)?.full_name ?? null, mall_assignments: c.malls, branch_assignments: c.branches, store_assignments: c.stores };
    });
  const { items, totalCount } = listInMemory(rows, { search, searchFields: ['email', 'full_name'], sortColumn, sortOrder, offset, pageSize });
  return { items: items.map(toPublic), totalCount };
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
 * first, at most [limit]. `total` is the full count.
 */
export async function findByFullName(fullName, limit = 3) {
  const want = fullName.trim().toLowerCase();
  const rows = (await all(col('users')))
    .filter((u) => String(u.full_name).trim().toLowerCase() === want)
    .sort((a, b) => b.created_at - a.created_at);
  return { total: rows.length, items: rows.slice(0, limit).map((x) => ({ id: x.id, fullName: x.full_name, role: x.role, isActive: !!x.is_active })) };
}

