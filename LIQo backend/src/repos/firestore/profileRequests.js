// Profile change requests on Firestore (P1-06A). One waiting request per
// person: a guard doc _unique/profile_pending:<userId> (SQL: filtered unique index).
import { col, docOf, runTx, nextId, one, all, uniqueRef, Timestamp } from '../../db/firestore.js';
import { byId, dupError } from './util.js';

export function toPublic(r) {
  if (!r) return null;
  return {
    id: r.id,
    userId: r.user_id,
    role: r.user_role,
    userActive: !!r.user_active,
    current: { fullName: r.current_name, email: r.current_email },
    requested: { fullName: r.full_name, email: r.email },
    status: r.status,
    reason: r.reason ?? null,
    reviewedBy: r.reviewer_name ?? null,
    reviewedAt: r.reviewed_at ?? null,
    createdAt: r.created_at,
  };
}

async function shape(r, users = null) {
  if (!r) return null;
  const u = users ?? byId(await all(col('users')));
  const owner = u.get(r.user_id);
  return toPublic({
    ...r,
    current_name: owner?.full_name ?? null,
    current_email: owner?.email ?? null,
    user_role: owner?.role ?? null,
    user_active: owner?.is_active ?? false,
    reviewer_name: r.reviewed_by != null ? u.get(r.reviewed_by)?.full_name ?? null : null,
  });
}

export async function findById(id) {
  return shape(await one('profile_requests', Number(id)));
}

/** The person's waiting request, else their most recent one, else null. */
export async function latestForUser(userId) {
  const rows = await all(col('profile_requests').where('user_id', '==', Number(userId)));
  rows.sort((a, b) => Number(b.status === 'pending') - Number(a.status === 'pending') || b.id - a.id);
  return shape(rows[0] ?? null);
}

/** Is this email waiting in someone else's request? */
export async function emailPendingForOther(email, userId) {
  const rows = await all(col('profile_requests').where('status', '==', 'pending'));
  return rows.some((r) => String(r.email).toLowerCase() === String(email).toLowerCase() && r.user_id !== Number(userId));
}

/** Creates a waiting request. Throws 'ALREADY_PENDING' when one is waiting. */
export async function create({ userId, fullName, email }) {
  const id = await runTx(async (tx) => {
    const guard = uniqueRef('profile_pending', userId);
    if ((await tx.get(guard)).exists) throw new Error('ALREADY_PENDING');
    const nid = await nextId('profile_requests', tx);
    tx.set(guard, { id: nid });
    tx.set(docOf('profile_requests', nid), { id: nid, user_id: Number(userId), full_name: fullName, email, status: 'pending', reason: null, reviewed_by: null, reviewed_at: null, created_at: Timestamp.now() });
    return nid;
  });
  return findById(id);
}

/** Moves a waiting request to a final status. Returns the request, or null when it was not waiting. */
export async function decide(id, { status, reason = null, reviewedBy = null }) {
  const ok = await runTx(async (tx) => {
    const ref = docOf('profile_requests', id);
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== 'pending') return false;
    tx.update(ref, { status, reason, reviewed_by: reviewedBy, reviewed_at: Timestamp.now() });
    tx.delete(uniqueRef('profile_pending', snap.data().user_id));
    return true;
  });
  return ok ? findById(id) : null;
}

/** Cancels the person's waiting request. Returns it, or null when nothing was waiting. */
export async function cancelForUser(userId) {
  const pending = (await all(col('profile_requests').where('user_id', '==', Number(userId)))).find((r) => r.status === 'pending');
  if (!pending) return null;
  const ok = await runTx(async (tx) => {
    const ref = docOf('profile_requests', pending.id);
    const snap = await tx.get(ref);
    if (snap.data().status !== 'pending') return false;
    tx.update(ref, { status: 'cancelled', reviewed_at: Timestamp.now() });
    tx.delete(uniqueRef('profile_pending', userId));
    return true;
  });
  return ok ? findById(pending.id) : null;
}

/** Applies the request to the account and marks it approved, in one transaction. Null when it was not waiting. */
export async function approve(id, reviewedBy) {
  const done = await runTx(async (tx) => {
    const ref = docOf('profile_requests', id);
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== 'pending') return false;
    const r = snap.data();
    const userRef = docOf('users', r.user_id);
    const u = (await tx.get(userRef)).data();
    // The email stays unique (SQL: UNIQUE on users.email).
    if (String(u.email).toLowerCase() !== String(r.email).toLowerCase()) {
      const guard = uniqueRef('email', r.email);
      const g = await tx.get(guard);
      if (g.exists && g.data().userId !== r.user_id) throw dupError();
      tx.delete(uniqueRef('email', u.email));
      tx.set(guard, { userId: r.user_id });
    }
    tx.update(ref, { status: 'approved', reviewed_by: reviewedBy, reviewed_at: Timestamp.now() });
    tx.delete(uniqueRef('profile_pending', r.user_id));
    tx.update(userRef, { full_name: r.full_name, email: r.email, email_lc: String(r.email).toLowerCase(), updated_at: Timestamp.now() });
    return true;
  });
  return done ? findById(id) : null;
}

export async function list({ status, userId, offset, pageSize }) {
  const [rows, users] = await Promise.all([all(col('profile_requests')), all(col('users'))]);
  const u = byId(users);
  const filtered = rows
    .filter((r) => !status || status === 'all' || r.status === status)
    .filter((r) => !userId || r.user_id === Number(userId))
    .sort((a, b) => b.created_at - a.created_at || b.id - a.id);
  const page = filtered.slice(offset, offset + pageSize);
  return { items: await Promise.all(page.map((r) => shape(r, u))), totalCount: filtered.length };
}
