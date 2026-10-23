// Problem reports and the Requests & reports counts (Round 19, owner decisions 2026-10-23).
//   Reporter (mall owner, mall admin, store owner): POST /reports, GET /reports/mine,
//     GET /reports/:id, POST /reports/:id/messages (while open)
//   Superadmin: GET /reports, GET /reports/:id, POST /reports/:id/messages,
//     PUT /reports/:id/status, GET /requests/counts
import { Router } from 'express';
import { z } from 'zod';
import { requireRole } from '../middleware/requireRole.js';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as reports from '../repos/reports.js';
import * as profileRequests from '../repos/profileRequests.js';
import * as credits from '../repos/credits.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';

export const reportsRouter = Router();
export const requestsRouter = Router();

export const REPORT_TYPES = ['broken', 'wrong_data', 'question', 'idea'];

const createSchema = z.object({
  type: z.enum(REPORT_TYPES, { errorMap: () => ({ message: 'Choose what kind of problem it is.' }) }),
  subject: z.string().trim().min(3, 'Write a short subject.').max(120),
  body: z.string().trim().min(5, 'Describe the problem in a few words.').max(2000),
  pagePath: z.string().trim().max(300).optional(),
});

const messageSchema = z.object({ body: z.string().trim().min(1, 'Write a message first.').max(2000) });

// Forward only: new → in progress → resolved or closed (without a fix).
const NEXT = { new: ['in_progress', 'resolved', 'closed'], in_progress: ['resolved', 'closed'], resolved: [], closed: [] };

reportsRouter.post('/', validate(createSchema), async (req, res, next) => {
  try {
    if (req.user.role === 'superadmin') throw new AppError(400, 'Superadmins receive reports; they do not send them.');
    const created = await reports.create({ reporterId: req.user.id, ...req.body, pagePath: req.body.pagePath || null });
    await recordAudit(req, res, { action: 'problem_reported', entityType: 'problem_report', entityId: created.id, details: { type: created.type, subject: created.subject, pagePath: created.pagePath } });
    res.status(201).json({ report: created });
  } catch (err) {
    next(err);
  }
});

reportsRouter.get('/mine', async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: { updated: 'r.updated_at' }, defaultSort: 'updated' });
    const { items, totalCount } = await reports.list({ reporterId: req.user.id, offset: paging.offset, pageSize: paging.pageSize });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

reportsRouter.get('/', requireRole(), async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: { updated: 'r.updated_at' }, defaultSort: 'updated' });
    // Like the other tabs: waiting by default; 'all' shows everything.
    const asked = req.query.status || 'waiting';
    const status = ['new', 'in_progress', 'resolved', 'closed', 'open', 'waiting'].includes(asked) ? asked : null;
    const type = REPORT_TYPES.includes(req.query.type) ? req.query.type : null;
    const { items, totalCount } = await reports.list({ status, type, offset: paging.offset, pageSize: paging.pageSize });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

/** The report, for its reporter or a superadmin only. */
async function loadReport(req) {
  const r = await reports.findById(Number(req.params.id));
  if (!r || (req.user.role !== 'superadmin' && r.reporterId !== req.user.id)) throw new AppError(404, 'Report not found.');
  return r;
}

reportsRouter.get('/:id', async (req, res, next) => {
  try {
    const r = await loadReport(req);
    res.json({ report: r, messages: await reports.messages(r.id) });
  } catch (err) {
    next(err);
  }
});

reportsRouter.post('/:id/messages', validate(messageSchema), async (req, res, next) => {
  try {
    const r = await loadReport(req);
    if (!r.open) throw new AppError(409, `This report is ${r.status === 'resolved' ? 'resolved' : 'closed'}, so no more messages can be added.`);
    if (!(await reports.addMessage(r.id, req.user.id, req.body.body))) throw new AppError(409, 'This report was closed a moment ago. Refresh the page.');
    await recordAudit(req, res, { action: 'problem_report_message', entityType: 'problem_report', entityId: r.id, details: { by: req.user.role } });
    res.status(201).json({ report: await reports.findById(r.id), messages: await reports.messages(r.id) });
  } catch (err) {
    next(err);
  }
});

reportsRouter.put(
  '/:id/status',
  requireRole(),
  validate(z.object({ status: z.enum(['in_progress', 'resolved', 'closed']) })),
  async (req, res, next) => {
    try {
      const r = await loadReport(req);
      if (!NEXT[r.status].includes(req.body.status)) throw new AppError(409, `A ${r.status.replace('_', ' ')} report cannot be moved to ${req.body.status.replace('_', ' ')}.`);
      if (!(await reports.setStatus(r.id, r.status, req.body.status, req.user.id))) throw new AppError(409, 'This report changed a moment ago. Refresh the page.');
      await recordAudit(req, res, { action: 'problem_report_status', entityType: 'problem_report', entityId: r.id, details: { from: r.status, to: req.body.status } });
      res.json({ report: await reports.findById(r.id), messages: await reports.messages(r.id) });
    } catch (err) {
      next(err);
    }
  },
);

/** What waits for a superadmin on Requests & reports, per tab and in total (the sidebar count). */
requestsRouter.get('/counts', requireRole(), async (req, res, next) => {
  try {
    const [profile, creditRequests, problems] = await Promise.all([
      profileRequests.list({ status: 'pending', userId: null, offset: 0, pageSize: 1 }).then((x) => x.totalCount),
      credits.pendingRequestCount(),
      reports.waitingCount(),
    ]);
    res.json({ profile, credits: creditRequests, reports: problems, total: profile + creditRequests + problems });
  } catch (err) {
    next(err);
  }
});
