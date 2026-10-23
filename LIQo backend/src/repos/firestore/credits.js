// AI credits per mall admin on Firestore (P1-06A). SQL Server holds an
// application lock for every credits write; here one server process holds an
// in-process lock instead, and the writes of one locked step are collected and
// committed together in one batch (all or nothing). Reads inside the step see
// the step's own earlier writes.
import { col, docOf, getDb, nextId, all, uniqueRef, Timestamp, fromStore } from '../../db/firestore.js';
import { round4 } from '../../ai/credits.js';
import { byId, compare } from './util.js';

const num = (v) => (v == null ? null : Number(v));

/** The writes of one locked step. */
class Unit {
  constructor() {
    this.writes = new Map();
  }
  async get(ref) {
    if (this.writes.has(ref.path)) return this.writes.get(ref.path).data;
    const snap = await ref.get();
    return snap.exists ? fromStore(snap.data()) : null;
  }
  set(ref, data) {
    this.writes.set(ref.path, { ref, data });
  }
  delete(ref) {
    this.writes.set(ref.path, { ref, data: null });
  }
  async commit() {
    if (this.writes.size === 0) return;
    const batch = getDb().batch();
    for (const { ref, data } of this.writes.values()) {
      if (data == null) batch.delete(ref);
      else batch.set(ref, data);
    }
    await batch.commit();
  }
}

let chain = Promise.resolve();
/** Runs [fn] holding the credits lock; its writes are committed together when it succeeds. */
export function withCreditsLock(fn) {
  const run = chain.then(async () => {
    const unit = new Unit();
    const out = await fn(unit);
    await unit.commit();
    return out;
  });
  chain = run.catch(() => {});
  return run;
}

const read = (tx, ref) => (tx ? tx.get(ref) : ref.get().then((s) => (s.exists ? fromStore(s.data()) : null)));

/** What active mall admins hold and have not used (negative balances count as 0). */
export async function givenTotal(tx = null) {
  const [balances, users] = await Promise.all([all(col('ai_credit_balances')), all(col('users'))]);
  const u = byId(users);
  let given = 0;
  for (const b of balances) {
    const cur = tx ? (await tx.get(docOf('ai_credit_balances', b.user_id))) ?? b : b;
    const owner = u.get(b.user_id);
    if (owner?.role === 'mall_admin' && owner.is_active && cur.balance > 0) given += cur.balance;
  }
  return round4(given);
}

/** An admin's balance and full mark (0 and null when they never had credits). */
export async function balanceOf(userId, tx = null) {
  const row = await read(tx, docOf('ai_credit_balances', userId));
  return { balance: row ? round4(row.balance) : 0, full: row ? num(row.full_mark) : null };
}

/**
 * Changes a balance by [delta] and writes the ledger row, inside [tx].
 * A top-up (giving, starting, an approved request) makes the new balance the
 * bar's full mark. Returns the balance after.
 */
export async function change(tx, { userId, delta, kind, actorId = null, note = null, conversionId = null, requestId = null }) {
  const topUp = delta > 0 && ['start', 'grant', 'request'].includes(kind);
  const ref = docOf('ai_credit_balances', userId);
  const cur = await tx.get(ref);
  let row;
  if (cur) {
    const after = cur.balance + delta;
    const full = topUp ? after : cur.full_mark == null || cur.full_mark < after ? after : cur.full_mark;
    row = { ...cur, balance: round4(after), full_mark: full, updated_at: new Date() };
  } else {
    row = { user_id: Number(userId), balance: round4(delta), full_mark: delta > 0 ? delta : null, updated_at: new Date() };
  }
  tx.set(ref, row);
  const after = round4(row.balance);
  const id = await nextId('ai_credit_ledger');
  tx.set(docOf('ai_credit_ledger', id), {
    id,
    user_id: Number(userId),
    delta,
    balance_after: after,
    kind,
    conversion_id: conversionId,
    request_id: requestId,
    actor_id: actorId,
    note,
    created_at: new Date(),
  });
  return after;
}

/** Is this user an active mall admin (the only people with balances)? */
export async function isActiveMallAdmin(userId) {
  const u = await read(null, docOf('users', userId));
  return !!u && u.role === 'mall_admin' && !!u.is_active;
}

const since = (days) => Timestamp.fromDate(new Date(Date.now() - days * 24 * 3600 * 1000));

async function firstBranchNames() {
  const [links, branches] = await Promise.all([all(col('mall_admin_assignments')), all(col('branches'))]);
  const b = byId(branches);
  const out = new Map();
  for (const l of links.sort((x, y) => x.branch_id - y.branch_id)) if (!out.has(l.user_id)) out.set(l.user_id, b.get(l.branch_id)?.name ?? null);
  return out;
}

/**
 * Mall admins with their balance and use: all active ones, or only those
 * reporting to [reportsTo] (a mall owner's view). Use covers the last [days].
 */
export async function adminRows({ days, reportsTo = null }) {
  const [users, balances, recent, readings, branchNames] = await Promise.all([
    all(col('users').where('role', '==', 'mall_admin')),
    all(col('ai_credit_balances')),
    all(col('map_conversions').where('requested_at', '>=', since(days))),
    all(col('map_conversions').where('used_ai', '==', true)),
    firstBranchNames(),
  ]);
  const bal = new Map(balances.map((b) => [b.user_id, b]));
  return users
    .filter((u) => u.is_active && (reportsTo == null || u.reports_to === Number(reportsTo)))
    .sort((a, b) => compare(a.full_name, b.full_name))
    .map((u) => {
      const mine = recent.filter((c) => c.requested_by === u.id);
      const last = readings.filter((c) => c.requested_by === u.id).reduce((m, c) => (!m || c.requested_at > m ? c.requested_at : m), null);
      const b = bal.get(u.id);
      return {
        id: u.id,
        name: u.full_name,
        email: u.email,
        branch: branchNames.get(u.id) ?? null,
        balance: round4(b?.balance ?? 0),
        full: num(b?.full_mark ?? null),
        used: round4(mine.reduce((a, c) => a + (c.credits ?? 0), 0)),
        readings: mine.filter((c) => c.used_ai).length,
        lastReading: last,
      };
    });
}

/** The calendar day of a time on this server (SQL: CAST(requested_at AS DATE)). */
const localDay = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Credits used per day over the last [days]: everyone's readings, or only these users'. */
export async function usageSeries({ days, userIds = null }) {
  if (userIds && userIds.length === 0) return { total: 0, series: [] };
  const wanted = userIds ? new Set(userIds.map(Number)) : null;
  const rows = (await all(col('map_conversions').where('requested_at', '>=', since(days)))).filter((c) => !wanted || wanted.has(c.requested_by));
  const byDay = new Map();
  for (const c of rows) {
    const key = localDay(c.requested_at);
    const cur = byDay.get(key) ?? { credits: 0, readings: 0 };
    cur.credits += c.credits ?? 0;
    cur.readings += c.used_ai ? 1 : 0;
    byDay.set(key, cur);
  }
  const series = [...byDay.entries()]
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([day, v]) => {
      const [y, m, d] = day.split('-').map(Number);
      return { day: new Date(y, m - 1, d), credits: round4(v.credits), readings: v.readings };
    });
  return { total: round4(series.reduce((a, x) => a + x.credits, 0)), series };
}

/** The average paid reading over the last 30 days (for the low-balance warning). */
export async function avgCost() {
  const paid = (await all(col('map_conversions').where('requested_at', '>=', since(30)))).filter((c) => c.credits > 0);
  return paid.length ? round4(paid.reduce((a, c) => a + c.credits, 0) / paid.length) : null;
}

/** Ledger rows, newest first, with names. */
export async function history({ userId = null, offset, pageSize }) {
  const q = userId == null ? col('ai_credit_ledger') : col('ai_credit_ledger').where('user_id', '==', Number(userId));
  const [rows, users] = await Promise.all([all(q), all(col('users'))]);
  const u = byId(users);
  rows.sort((a, b) => b.id - a.id);
  return {
    totalCount: rows.length,
    items: rows.slice(offset, offset + pageSize).map((x) => ({
      id: x.id,
      userId: x.user_id,
      user: u.get(x.user_id)?.full_name ?? null,
      delta: round4(x.delta),
      balanceAfter: round4(x.balance_after),
      kind: x.kind,
      note: x.note ?? null,
      conversionId: x.conversion_id ?? null,
      requestId: x.request_id ?? null,
      actor: x.actor_id != null ? u.get(x.actor_id)?.full_name ?? null : null,
      createdAt: x.created_at,
    })),
  };
}

// ---- Requests ----

async function requestToPublic(x, tx = null) {
  if (!x) return null;
  const [user, bal, branchNames, decider] = await Promise.all([
    read(null, docOf('users', x.user_id)),
    read(tx, docOf('ai_credit_balances', x.user_id)),
    firstBranchNames(),
    x.decided_by != null ? read(null, docOf('users', x.decided_by)) : null,
  ]);
  return {
    id: x.id,
    userId: x.user_id,
    user: user?.full_name ?? null,
    email: user?.email ?? null,
    userActive: !!user?.is_active,
    branch: branchNames.get(x.user_id) ?? null,
    balance: round4(bal?.balance ?? 0),
    amount: round4(x.amount),
    status: x.status,
    decidedAmount: x.decided_amount == null ? null : round4(x.decided_amount),
    decidedBy: decider?.full_name ?? null,
    declineReason: x.decline_reason ?? null,
    createdAt: x.created_at,
    decidedAt: x.decided_at ?? null,
  };
}

export async function findRequest(id, tx = null) {
  return requestToPublic(await read(tx, docOf('ai_credit_requests', id)), tx);
}

/** The admin's open request, else their latest one, else null. */
export async function latestRequestFor(userId) {
  const rows = await all(col('ai_credit_requests').where('user_id', '==', Number(userId)));
  rows.sort((a, b) => Number(b.status === 'pending') - Number(a.status === 'pending') || b.id - a.id);
  return requestToPublic(rows[0] ?? null);
}

/** Opens a request. Throws 'ALREADY_PENDING' when one is open. */
export async function createRequest(userId, amount) {
  const id = await getDb().runTransaction(async (t) => {
    const guard = uniqueRef('credit_pending', userId);
    if ((await t.get(guard)).exists) throw new Error('ALREADY_PENDING');
    const nid = await nextId('ai_credit_requests', t);
    t.set(guard, { id: nid });
    t.set(docOf('ai_credit_requests', nid), {
      id: nid,
      user_id: Number(userId),
      amount,
      status: 'pending',
      decided_amount: null,
      decline_reason: null,
      decided_by: null,
      decided_at: null,
      created_at: Timestamp.now(),
    });
    return nid;
  });
  return findRequest(id);
}

/** Closes the admin's open request (cancelled by them, or because they were deactivated). */
export async function cancelOpenRequest(userId, tx = null) {
  if (!tx) return withCreditsLock((unit) => cancelOpenRequest(userId, unit));
  const open = (await all(col('ai_credit_requests').where('user_id', '==', Number(userId)))).find((r) => r.status === 'pending');
  if (!open) return null;
  const ref = docOf('ai_credit_requests', open.id);
  const cur = await tx.get(ref);
  if (cur.status !== 'pending') return null;
  tx.set(ref, { ...cur, status: 'cancelled', decided_at: new Date() });
  tx.delete(uniqueRef('credit_pending', userId));
  return findRequest(open.id, tx);
}

/** Moves an open request to approved or declined. Returns false when it was not open any more. */
export async function decideRequest(tx, id, { status, amount = null, reason = null, by }) {
  const ref = docOf('ai_credit_requests', id);
  const cur = await tx.get(ref);
  if (!cur || cur.status !== 'pending') return false;
  tx.set(ref, { ...cur, status, decided_amount: amount, decline_reason: reason, decided_by: by, decided_at: new Date() });
  tx.delete(uniqueRef('credit_pending', cur.user_id));
  return true;
}

export async function listRequests({ status = 'pending', offset, pageSize }) {
  const q = status === 'all' ? col('ai_credit_requests') : col('ai_credit_requests').where('status', '==', status);
  const rows = await all(q);
  rows.sort((a, b) => Number(b.status === 'pending') - Number(a.status === 'pending') || b.created_at - a.created_at || b.id - a.id);
  const items = await Promise.all(rows.slice(offset, offset + pageSize).map((r) => requestToPublic(r)));
  return { items, totalCount: rows.length };
}

export async function pendingRequestCount() {
  const snap = await col('ai_credit_requests').where('status', '==', 'pending').count().get();
  return snap.data().count;
}
