// Profile change requests: a person asks to change their own name and email;
// a superadmin approves (the change is applied) or rejects (with a reason).
import { query, sql, withTransaction, txQuery } from '../db/pool.js';

const SELECT = `
  SELECT pr.id, pr.user_id, pr.full_name, pr.email, pr.status, pr.reason, pr.reviewed_at, pr.created_at,
         u.full_name AS current_name, u.email AS current_email, u.role AS user_role, u.is_active AS user_active,
         rv.full_name AS reviewer_name
    FROM profile_requests pr
    JOIN users u ON u.id = pr.user_id
    LEFT JOIN users rv ON rv.id = pr.reviewed_by`;

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

export async function findById(id) {
  const r = await query(`${SELECT} WHERE pr.id = @id`, { id: { type: sql.Int, value: id } });
  return toPublic(r.recordset[0]);
}

/** The person's waiting request, else their most recent one, else null. */
export async function latestForUser(userId) {
  const r = await query(
    `${SELECT} WHERE pr.user_id = @u ORDER BY CASE WHEN pr.status = 'pending' THEN 0 ELSE 1 END, pr.id DESC
      OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY`,
    { u: { type: sql.Int, value: userId } },
  );
  return toPublic(r.recordset[0]);
}

/** Is this email waiting in someone else's request? */
export async function emailPendingForOther(email, userId) {
  const r = await query(`SELECT COUNT(*) AS n FROM profile_requests WHERE status = 'pending' AND email = @e AND user_id <> @u`, {
    e: email,
    u: { type: sql.Int, value: userId },
  });
  return r.recordset[0].n > 0;
}

/** Creates a waiting request. Throws 'ALREADY_PENDING' when one is waiting. */
export async function create({ userId, fullName, email }) {
  try {
    const r = await query(
      `INSERT INTO profile_requests (user_id, full_name, email) OUTPUT inserted.id VALUES (@u, @n, @e)`,
      { u: { type: sql.Int, value: userId }, n: fullName, e: email },
    );
    return findById(r.recordset[0].id);
  } catch (err) {
    if (err.number === 2601 || err.number === 2627) throw new Error('ALREADY_PENDING');
    throw err;
  }
}

/** Moves a waiting request to a final status. Returns the request, or null when it was not waiting. */
export async function decide(id, { status, reason = null, reviewedBy = null }) {
  const r = await query(
    `UPDATE profile_requests SET status = @s, reason = @r, reviewed_by = @by, reviewed_at = SYSDATETIME()
      OUTPUT inserted.id WHERE id = @id AND status = 'pending'`,
    {
      id: { type: sql.Int, value: id },
      s: status,
      r: reason,
      by: reviewedBy == null ? null : { type: sql.Int, value: reviewedBy },
    },
  );
  return r.recordset[0] ? findById(id) : null;
}

/** Cancels the person's waiting request. Returns it, or null when nothing was waiting. */
export async function cancelForUser(userId) {
  const r = await query(
    `UPDATE profile_requests SET status = 'cancelled', reviewed_at = SYSDATETIME()
      OUTPUT inserted.id WHERE user_id = @u AND status = 'pending'`,
    { u: { type: sql.Int, value: userId } },
  );
  return r.recordset[0] ? findById(r.recordset[0].id) : null;
}

/** Applies the request to the account and marks it approved, in one transaction. Null when it was not waiting. */
export async function approve(id, reviewedBy) {
  const done = await withTransaction(async (tx) => {
    const marked = await txQuery(
      tx,
      `UPDATE profile_requests SET status = 'approved', reviewed_by = @by, reviewed_at = SYSDATETIME()
        OUTPUT inserted.user_id, inserted.full_name, inserted.email WHERE id = @id AND status = 'pending'`,
      { id: { type: sql.Int, value: id }, by: { type: sql.Int, value: reviewedBy } },
    );
    const row = marked.recordset[0];
    if (!row) return false;
    await txQuery(tx, `UPDATE users SET full_name = @n, email = @e, updated_at = SYSDATETIME() WHERE id = @u`, {
      u: { type: sql.Int, value: row.user_id },
      n: row.full_name,
      e: row.email,
    });
    return true;
  });
  return done ? findById(id) : null;
}

export async function list({ status, userId, offset, pageSize }) {
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (status && status !== 'all') {
    where.push('pr.status = @status');
    params.status = status;
  }
  if (userId) {
    where.push('pr.user_id = @userId');
    params.userId = { type: sql.Int, value: userId };
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const total = (await query(`SELECT COUNT(*) AS n FROM profile_requests pr ${whereSql}`, params)).recordset[0].n;
  const rows = (await query(`${SELECT} ${whereSql} ORDER BY pr.created_at DESC OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`, params)).recordset;
  return { items: rows.map(toPublic), totalCount: total };
}
