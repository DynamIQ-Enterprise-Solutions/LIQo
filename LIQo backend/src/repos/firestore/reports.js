// Problem reports on Firestore (P1-06A). The report keeps its message count
// and the last author, updated with each message, so lists never read threads.
import { col, docOf, runTx, nextId, one, all, Timestamp } from '../../db/firestore.js';
import { byId } from './util.js';

const OPEN = ['new', 'in_progress'];
const waiting = (r) => r.status === 'new' || (r.status === 'in_progress' && r.last_author === r.reporter_id);

function toPublic(x, users) {
  if (!x) return null;
  const reporter = users.get(x.reporter_id);
  return {
    id: x.id,
    reporterId: x.reporter_id,
    reporter: reporter?.full_name ?? null,
    reporterEmail: reporter?.email ?? null,
    reporterRole: reporter?.role ?? null,
    type: x.type,
    subject: x.subject,
    body: x.body,
    pagePath: x.page_path ?? null,
    status: x.status,
    open: OPEN.includes(x.status),
    messageCount: x.message_count ?? 0,
    // The superadmin still owes an answer.
    waiting: waiting(x),
    createdAt: x.created_at,
    updatedAt: x.updated_at,
    closedAt: x.closed_at ?? null,
    closedBy: x.closed_by != null ? users.get(x.closed_by)?.full_name ?? null : null,
  };
}

const usersMap = async () => byId(await all(col('users')));

export async function findById(id) {
  const r = await one('problem_reports', Number(id));
  return r ? toPublic(r, await usersMap()) : null;
}

export async function create({ reporterId, type, subject, body, pagePath }) {
  const id = await runTx(async (tx) => {
    const nid = await nextId('problem_reports', tx);
    const now = Timestamp.now();
    tx.set(docOf('problem_reports', nid), {
      id: nid,
      reporter_id: Number(reporterId),
      type,
      subject,
      body,
      page_path: pagePath ?? null,
      status: 'new',
      message_count: 0,
      last_author: null,
      closed_at: null,
      closed_by: null,
      created_at: now,
      updated_at: now,
    });
    return nid;
  });
  return findById(id);
}

export async function list({ reporterId = null, status = null, type = null, offset, pageSize }) {
  const q = reporterId != null ? col('problem_reports').where('reporter_id', '==', Number(reporterId)) : col('problem_reports');
  const [rows, users] = await Promise.all([all(q), usersMap()]);
  const filtered = rows
    .filter((r) => {
      if (status === 'open') return OPEN.includes(r.status);
      if (status === 'waiting') return waiting(r);
      return !status || r.status === status;
    })
    .filter((r) => !type || r.type === type)
    .sort((a, b) => Number(OPEN.includes(b.status)) - Number(OPEN.includes(a.status)) || b.updated_at - a.updated_at);
  return { items: filtered.slice(offset, offset + pageSize).map((r) => toPublic(r, users)), totalCount: filtered.length };
}

export async function messages(reportId) {
  const [rows, users] = await Promise.all([all(col('problem_report_messages').where('report_id', '==', Number(reportId))), usersMap()]);
  return rows
    .sort((a, b) => a.id - b.id)
    .map((x) => {
      const a = users.get(x.author_id);
      return { id: x.id, authorId: x.author_id, author: a?.full_name ?? null, authorRole: a?.role ?? null, body: x.body, createdAt: x.created_at };
    });
}

/** Adds a message to an open report. Returns false when the report is not open any more. */
export async function addMessage(reportId, authorId, body) {
  return runTx(async (tx) => {
    const ref = docOf('problem_reports', reportId);
    const snap = await tx.get(ref);
    if (!snap.exists || !OPEN.includes(snap.data().status)) return false;
    const id = await nextId('problem_report_messages', tx);
    const now = Timestamp.now();
    tx.set(docOf('problem_report_messages', id), { id, report_id: Number(reportId), author_id: Number(authorId), body, created_at: now });
    tx.update(ref, { updated_at: now, message_count: (snap.data().message_count ?? 0) + 1, last_author: Number(authorId) });
    return true;
  });
}

/** Moves a report on (new → in progress → resolved or closed). Returns false when it changed meanwhile. */
export async function setStatus(reportId, from, to, by) {
  const closing = to === 'resolved' || to === 'closed';
  return runTx(async (tx) => {
    const ref = docOf('problem_reports', reportId);
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== from) return false;
    const now = Timestamp.now();
    tx.update(ref, { status: to, updated_at: now, closed_at: closing ? now : null, closed_by: closing ? Number(by) : null });
    return true;
  });
}

export async function waitingCount() {
  return (await all(col('problem_reports').where('status', 'in', OPEN))).filter(waiting).length;
}
