// AI credits per mall admin (Round 19): balances, the ledger and requests.
// Every write runs inside a transaction holding one application lock, so two
// clicks (or two admins) can never both pass the wallet and cap checks.
import { query, sql, withTransaction, txQuery } from '../../db/pool.js';
import { round4 } from '../../ai/credits.js';

const int = (v) => ({ type: sql.Int, value: v });
const dec = (v) => ({ type: sql.Decimal(12, 4), value: v });
const num = (v) => (v == null ? null : Number(v));

/** Runs [fn] in a transaction that holds the credits lock. */
export function withCreditsLock(fn) {
  return withTransaction(async (tx) => {
    await txQuery(tx, `EXEC sp_getapplock @Resource = 'liqo_ai_credits', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000`);
    return fn(tx);
  });
}

const run = (tx, text, params) => (tx ? txQuery(tx, text, params) : query(text, params));

/** What active mall admins hold and have not used (negative balances count as 0). */
export async function givenTotal(tx = null) {
  const r = await run(
    tx,
    `SELECT ISNULL(SUM(CASE WHEN b.balance > 0 THEN b.balance ELSE 0 END), 0) AS given
       FROM ai_credit_balances b JOIN users u ON u.id = b.user_id
      WHERE u.role = 'mall_admin' AND u.is_active = 1`,
  );
  return round4(r.recordset[0].given);
}

/** An admin's balance and full mark (0 and null when they never had credits). */
export async function balanceOf(userId, tx = null) {
  const r = await run(tx, `SELECT balance, full_mark FROM ai_credit_balances WHERE user_id = @u`, { u: int(userId) });
  const row = r.recordset[0];
  return { balance: row ? round4(row.balance) : 0, full: row ? num(row.full_mark) : null };
}

/**
 * Changes a balance by [delta] and writes the ledger row, inside [tx].
 * A top-up (giving, starting, an approved request) makes the new balance the
 * bar's full mark. Returns the balance after.
 */
export async function change(tx, { userId, delta, kind, actorId = null, note = null, conversionId = null, requestId = null }) {
  const topUp = delta > 0 && ['start', 'grant', 'request'].includes(kind);
  const r = await txQuery(
    tx,
    `MERGE ai_credit_balances AS t
     USING (SELECT @u AS user_id) AS s ON t.user_id = s.user_id
     WHEN MATCHED THEN UPDATE SET
       balance = t.balance + @d,
       full_mark = CASE WHEN @top = 1 THEN t.balance + @d
                        WHEN t.full_mark IS NULL OR t.full_mark < t.balance + @d THEN t.balance + @d
                        ELSE t.full_mark END,
       updated_at = SYSDATETIME()
     WHEN NOT MATCHED THEN INSERT (user_id, balance, full_mark) VALUES (@u, @d, CASE WHEN @d > 0 THEN @d ELSE NULL END)
     OUTPUT inserted.balance;`,
    { u: int(userId), d: dec(delta), top: { type: sql.Bit, value: topUp } },
  );
  const after = round4(r.recordset[0].balance);
  await txQuery(
    tx,
    `INSERT INTO ai_credit_ledger (user_id, delta, balance_after, kind, conversion_id, request_id, actor_id, note)
     VALUES (@u, @d, @a, @k, @c, @r, @by, @n)`,
    {
      u: int(userId),
      d: dec(delta),
      a: dec(after),
      k: kind,
      c: conversionId == null ? null : int(conversionId),
      r: requestId == null ? null : int(requestId),
      by: actorId == null ? null : int(actorId),
      n: note,
    },
  );
  return after;
}

/** Is this user an active mall admin (the only people with balances)? */
export async function isActiveMallAdmin(userId, tx = null) {
  const r = await run(tx, `SELECT 1 AS ok FROM users WHERE id = @u AND role = 'mall_admin' AND is_active = 1`, { u: int(userId) });
  return r.recordset.length > 0;
}

/**
 * Mall admins with their balance and use: all active ones, or only those
 * reporting to [reportsTo] (a mall owner's view). Use covers the last [days].
 */
export async function adminRows({ days, reportsTo = null }) {
  const r = await query(
    `SELECT u.id, u.full_name, u.email,
            (SELECT TOP 1 b.name FROM mall_admin_assignments ma JOIN branches b ON b.id = ma.branch_id WHERE ma.user_id = u.id) AS branch_name,
            ISNULL(cb.balance, 0) AS balance, cb.full_mark,
            ISNULL(us.used, 0) AS used, ISNULL(us.readings, 0) AS readings, lr.last_reading
       FROM users u
       LEFT JOIN ai_credit_balances cb ON cb.user_id = u.id
       OUTER APPLY (SELECT SUM(ISNULL(mc.credits, 0)) AS used, SUM(CASE WHEN mc.used_ai = 1 THEN 1 ELSE 0 END) AS readings
                      FROM map_conversions mc
                     WHERE mc.requested_by = u.id AND mc.requested_at >= DATEADD(day, -@days, SYSDATETIME())) us
       OUTER APPLY (SELECT MAX(mc.requested_at) AS last_reading FROM map_conversions mc WHERE mc.requested_by = u.id AND mc.used_ai = 1) lr
      WHERE u.role = 'mall_admin' AND u.is_active = 1 ${reportsTo == null ? '' : 'AND u.reports_to = @owner'}
      ORDER BY u.full_name`,
    { days: int(days), ...(reportsTo == null ? {} : { owner: int(reportsTo) }) },
  );
  return r.recordset.map((x) => ({
    id: x.id,
    name: x.full_name,
    email: x.email,
    branch: x.branch_name ?? null,
    balance: round4(x.balance),
    full: num(x.full_mark),
    used: round4(x.used),
    readings: x.readings,
    lastReading: x.last_reading ?? null,
  }));
}

/** Credits used per day over the last [days]: everyone's readings, or only these users'. */
export async function usageSeries({ days, userIds = null }) {
  if (userIds && userIds.length === 0) return { total: 0, series: [] };
  const params = { days: int(days) };
  let filter = '';
  if (userIds) {
    filter = `AND requested_by IN (${userIds.map((_, i) => `@u${i}`).join(', ')})`;
    userIds.forEach((id, i) => {
      params[`u${i}`] = int(id);
    });
  }
  const r = await query(
    `SELECT CAST(requested_at AS DATE) AS day, SUM(ISNULL(credits, 0)) AS credits, SUM(CASE WHEN used_ai = 1 THEN 1 ELSE 0 END) AS readings
       FROM map_conversions
      WHERE requested_at >= DATEADD(day, -@days, SYSDATETIME()) ${filter}
      GROUP BY CAST(requested_at AS DATE) ORDER BY day`,
    params,
  );
  const series = r.recordset.map((x) => ({ day: x.day, credits: round4(x.credits), readings: x.readings }));
  return { total: round4(series.reduce((a, x) => a + x.credits, 0)), series };
}

/** The average paid reading over the last 30 days (for the low-balance warning). */
export async function avgCost() {
  const r = await query(`SELECT AVG(credits) AS avg FROM map_conversions WHERE credits > 0 AND requested_at >= DATEADD(day, -30, SYSDATETIME())`);
  return r.recordset[0].avg == null ? null : round4(r.recordset[0].avg);
}

/** Ledger rows, newest first, with names. */
export async function history({ userId = null, offset, pageSize }) {
  const where = userId == null ? '' : 'WHERE l.user_id = @u';
  const params = { off: int(offset), ps: int(pageSize), ...(userId == null ? {} : { u: int(userId) }) };
  const r = await query(
    `SELECT l.id, l.user_id, u.full_name AS user_name, l.delta, l.balance_after, l.kind, l.note, l.conversion_id, l.request_id,
            l.actor_id, a.full_name AS actor_name, l.created_at, COUNT(*) OVER () AS total
       FROM ai_credit_ledger l
       JOIN users u ON u.id = l.user_id
       LEFT JOIN users a ON a.id = l.actor_id
       ${where}
      ORDER BY l.id DESC OFFSET @off ROWS FETCH NEXT @ps ROWS ONLY`,
    params,
  );
  const total = r.recordset[0]?.total ?? 0;
  if (total === 0 && offset > 0) {
    const c = await query(`SELECT COUNT(*) AS n FROM ai_credit_ledger l ${where}`, userId == null ? {} : { u: int(userId) });
    return { items: [], totalCount: c.recordset[0].n };
  }
  return {
    totalCount: total,
    items: r.recordset.map((x) => ({
      id: x.id,
      userId: x.user_id,
      user: x.user_name,
      delta: round4(x.delta),
      balanceAfter: round4(x.balance_after),
      kind: x.kind,
      note: x.note ?? null,
      conversionId: x.conversion_id ?? null,
      requestId: x.request_id ?? null,
      actor: x.actor_name ?? null,
      createdAt: x.created_at,
    })),
  };
}

// ---- Requests ----

const REQUEST_SELECT = `
  SELECT r.id, r.user_id, u.full_name AS user_name, u.email AS user_email, u.is_active AS user_active,
         (SELECT TOP 1 b.name FROM mall_admin_assignments ma JOIN branches b ON b.id = ma.branch_id WHERE ma.user_id = r.user_id) AS branch_name,
         ISNULL(cb.balance, 0) AS balance, r.amount, r.status, r.decided_amount, d.full_name AS decider_name, r.decline_reason,
         r.created_at, r.decided_at
    FROM ai_credit_requests r
    JOIN users u ON u.id = r.user_id
    LEFT JOIN ai_credit_balances cb ON cb.user_id = r.user_id
    LEFT JOIN users d ON d.id = r.decided_by`;

function requestToPublic(x) {
  if (!x) return null;
  return {
    id: x.id,
    userId: x.user_id,
    user: x.user_name,
    email: x.user_email,
    userActive: !!x.user_active,
    branch: x.branch_name ?? null,
    balance: round4(x.balance),
    amount: round4(x.amount),
    status: x.status,
    decidedAmount: x.decided_amount == null ? null : round4(x.decided_amount),
    decidedBy: x.decider_name ?? null,
    declineReason: x.decline_reason ?? null,
    createdAt: x.created_at,
    decidedAt: x.decided_at ?? null,
  };
}

export async function findRequest(id, tx = null) {
  const r = await run(tx, `${REQUEST_SELECT} WHERE r.id = @id`, { id: int(id) });
  return requestToPublic(r.recordset[0]);
}

/** The admin's open request, else their latest one, else null. */
export async function latestRequestFor(userId) {
  const r = await query(
    `${REQUEST_SELECT} WHERE r.user_id = @u ORDER BY CASE WHEN r.status = 'pending' THEN 0 ELSE 1 END, r.id DESC
      OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY`,
    { u: int(userId) },
  );
  return requestToPublic(r.recordset[0]);
}

/** Opens a request. Throws 'ALREADY_PENDING' when one is open. */
export async function createRequest(userId, amount) {
  try {
    const r = await query(`INSERT INTO ai_credit_requests (user_id, amount) OUTPUT inserted.id VALUES (@u, @a)`, { u: int(userId), a: dec(amount) });
    return findRequest(r.recordset[0].id);
  } catch (err) {
    if (err.number === 2601 || err.number === 2627) throw new Error('ALREADY_PENDING');
    throw err;
  }
}

/** Closes the admin's open request (cancelled by them, or because they were deactivated). */
export async function cancelOpenRequest(userId, tx = null) {
  const r = await run(
    tx,
    `UPDATE ai_credit_requests SET status = 'cancelled', decided_at = SYSDATETIME() OUTPUT inserted.id WHERE user_id = @u AND status = 'pending'`,
    { u: int(userId) },
  );
  return r.recordset[0] ? findRequest(r.recordset[0].id, tx) : null;
}

/** Moves an open request to approved or declined. Returns false when it was not open any more. */
export async function decideRequest(tx, id, { status, amount = null, reason = null, by }) {
  const r = await txQuery(
    tx,
    `UPDATE ai_credit_requests SET status = @s, decided_amount = @a, decline_reason = @r, decided_by = @by, decided_at = SYSDATETIME()
      OUTPUT inserted.id WHERE id = @id AND status = 'pending'`,
    { id: int(id), s: status, a: amount == null ? null : dec(amount), r: reason, by: int(by) },
  );
  return r.recordset.length > 0;
}

export async function listRequests({ status = 'pending', offset, pageSize }) {
  const all = status === 'all';
  const r = await query(
    `${REQUEST_SELECT} ${all ? '' : 'WHERE r.status = @s'}
      ORDER BY CASE WHEN r.status = 'pending' THEN 0 ELSE 1 END, r.created_at DESC
      OFFSET @off ROWS FETCH NEXT @ps ROWS ONLY`,
    { s: status, off: int(offset), ps: int(pageSize) },
  );
  const c = await query(`SELECT COUNT(*) AS n FROM ai_credit_requests r ${all ? '' : 'WHERE r.status = @s'}`, { s: status });
  return { items: r.recordset.map(requestToPublic), totalCount: c.recordset[0].n };
}

export async function pendingRequestCount() {
  const r = await query(`SELECT COUNT(*) AS n FROM ai_credit_requests WHERE status = 'pending'`);
  return r.recordset[0].n;
}
