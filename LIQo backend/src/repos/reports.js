// Problem reports (Round 19): mall owners, mall admins and store owners tell
// the superadmin about a problem; both sides talk in a thread until it is
// resolved or closed.
import { query, sql } from '../db/pool.js';

const int = (v) => ({ type: sql.Int, value: v });

const SELECT = `
  SELECT r.id, r.reporter_id, u.full_name AS reporter_name, u.email AS reporter_email, u.role AS reporter_role,
         r.type, r.subject, r.body, r.page_path, r.status, r.created_at, r.updated_at, r.closed_at, c.full_name AS closer_name,
         (SELECT COUNT(*) FROM problem_report_messages m WHERE m.report_id = r.id) AS message_count,
         (SELECT TOP 1 m.author_id FROM problem_report_messages m WHERE m.report_id = r.id ORDER BY m.id DESC) AS last_author
    FROM problem_reports r
    JOIN users u ON u.id = r.reporter_id
    LEFT JOIN users c ON c.id = r.closed_by`;

/** Waiting for the superadmin: new, or open with the reporter's message last. */
const WAITING = `(r.status = 'new' OR (r.status = 'in_progress' AND (SELECT TOP 1 m.author_id FROM problem_report_messages m WHERE m.report_id = r.id ORDER BY m.id DESC) = r.reporter_id))`;

function toPublic(x) {
  if (!x) return null;
  const open = x.status === 'new' || x.status === 'in_progress';
  return {
    id: x.id,
    reporterId: x.reporter_id,
    reporter: x.reporter_name,
    reporterEmail: x.reporter_email,
    reporterRole: x.reporter_role,
    type: x.type,
    subject: x.subject,
    body: x.body,
    pagePath: x.page_path ?? null,
    status: x.status,
    open,
    messageCount: x.message_count,
    // The superadmin still owes an answer.
    waiting: x.status === 'new' || (x.status === 'in_progress' && x.last_author === x.reporter_id),
    createdAt: x.created_at,
    updatedAt: x.updated_at,
    closedAt: x.closed_at ?? null,
    closedBy: x.closer_name ?? null,
  };
}

export async function findById(id) {
  const r = await query(`${SELECT} WHERE r.id = @id`, { id: int(id) });
  return toPublic(r.recordset[0]);
}

export async function create({ reporterId, type, subject, body, pagePath }) {
  const r = await query(
    `INSERT INTO problem_reports (reporter_id, type, subject, body, page_path) OUTPUT inserted.id VALUES (@u, @t, @s, @b, @p)`,
    { u: int(reporterId), t: type, s: subject, b: body, p: pagePath },
  );
  return findById(r.recordset[0].id);
}

export async function list({ reporterId = null, status = null, type = null, offset, pageSize }) {
  const where = [];
  const params = { off: int(offset), ps: int(pageSize) };
  if (reporterId != null) {
    where.push('r.reporter_id = @u');
    params.u = int(reporterId);
  }
  if (status === 'open') where.push(`r.status IN ('new', 'in_progress')`);
  else if (status === 'waiting') where.push(WAITING);
  else if (status) {
    where.push('r.status = @s');
    params.s = status;
  }
  if (type) {
    where.push('r.type = @t');
    params.t = type;
  }
  const w = where.length ? `WHERE ${where.join(' AND ')}` : '';
  const r = await query(
    `${SELECT} ${w}
      ORDER BY CASE WHEN r.status IN ('new', 'in_progress') THEN 0 ELSE 1 END, r.updated_at DESC
      OFFSET @off ROWS FETCH NEXT @ps ROWS ONLY`,
    params,
  );
  const c = await query(`SELECT COUNT(*) AS n FROM problem_reports r ${w}`, params);
  return { items: r.recordset.map(toPublic), totalCount: c.recordset[0].n };
}

export async function messages(reportId) {
  const r = await query(
    `SELECT m.id, m.author_id, u.full_name AS author_name, u.role AS author_role, m.body, m.created_at
       FROM problem_report_messages m JOIN users u ON u.id = m.author_id
      WHERE m.report_id = @id ORDER BY m.id`,
    { id: int(reportId) },
  );
  return r.recordset.map((x) => ({ id: x.id, authorId: x.author_id, author: x.author_name, authorRole: x.author_role, body: x.body, createdAt: x.created_at }));
}

/** Adds a message to an open report. Returns false when the report is not open any more. */
export async function addMessage(reportId, authorId, body) {
  const r = await query(
    `UPDATE problem_reports SET updated_at = SYSDATETIME() OUTPUT inserted.id WHERE id = @id AND status IN ('new', 'in_progress');
     IF @@ROWCOUNT = 1 INSERT INTO problem_report_messages (report_id, author_id, body) VALUES (@id, @a, @b);`,
    { id: int(reportId), a: int(authorId), b: body },
  );
  return r.recordset.length > 0;
}

/** Moves a report on (new → in progress → resolved or closed). Returns false when it changed meanwhile. */
export async function setStatus(reportId, from, to, by) {
  const closing = to === 'resolved' || to === 'closed';
  const r = await query(
    `UPDATE problem_reports SET status = @to, updated_at = SYSDATETIME(),
            closed_at = ${closing ? 'SYSDATETIME()' : 'NULL'}, closed_by = ${closing ? '@by' : 'NULL'}
      OUTPUT inserted.id WHERE id = @id AND status = @from`,
    { id: int(reportId), from, to, by: int(by) },
  );
  return r.recordset.length > 0;
}

export async function waitingCount() {
  const r = await query(`SELECT COUNT(*) AS n FROM problem_reports r WHERE ${WAITING}`);
  return r.recordset[0].n;
}
