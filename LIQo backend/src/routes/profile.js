// A person's own name and email (Round 8).
//   Superadmin: changes apply at once.            PUT /profile
//   Everyone else: a request a superadmin decides. GET/POST/DELETE /profile/request
//   Superadmin review:                             /profile-requests
import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as users from '../repos/users.js';
import * as requests from '../repos/profileRequests.js';
import * as assignments from '../repos/assignments.js';
import * as owners from '../repos/owners.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';

export const profileRouter = Router();
export const profileRequestsRouter = Router();

const detailsSchema = z.object({
  fullName: z.string().trim().min(2, 'Full name is required.').max(200),
  email: z.string().trim().toLowerCase().email('Enter a valid email address.').max(255),
});

/** The email must not belong to another account, nor wait in another person's request. */
async function assertEmailFree(email, userId) {
  const other = await users.findByEmail(email);
  if (other && other.id !== userId) throw new AppError(409, 'Another account already uses that email.');
  if (await requests.emailPendingForOther(email, userId)) throw new AppError(409, "That email is waiting in someone else's change request.");
}

// ---- Own account ----

/** Superadmin: change your own details at once. */
profileRouter.put('/', requireRole(), validate(detailsSchema), async (req, res, next) => {
  try {
    const me = req.user;
    await assertEmailFree(req.body.email, me.id);
    const updated = await users.updateProfile(me.id, req.body);
    await recordAudit(req, res, {
      action: 'profile_updated',
      entityType: 'user',
      entityId: me.id,
      details: { old: { fullName: me.full_name, email: me.email }, new: req.body },
    });
    res.json({ user: users.toPublic(updated) });
  } catch (err) {
    next(err);
  }
});

/** My waiting request, else my latest one, else null. */
/**
 * What the signed-in person owns or manages, for the "Your access" card on My
 * account (Round 14): an owner's malls and branches, an admin's branch and
 * superior, a store owner's stores. A superadmin has access to everything.
 */
profileRouter.get('/access', async (req, res, next) => {
  try {
    const me = await users.findById(req.user.id);
    const out = { role: me.role };
    if (me.role === 'supervisor') Object.assign(out, await assignments.supervisorAssignments(me.id));
    if (me.role === 'mall_admin') {
      Object.assign(out, await assignments.mallAdminAssignments(me.id));
      out.reportsTo = me.reports_to == null ? null : { id: me.reports_to, name: me.reports_to_name ?? null };
    }
    if (me.role === 'store_owner') out.stores = await owners.storesForOwner(me.id);
    res.json(out);
  } catch (err) {
    next(err);
  }
});

profileRouter.get('/request', async (req, res, next) => {
  try {
    res.json({ request: await requests.latestForUser(req.user.id) });
  } catch (err) {
    next(err);
  }
});

profileRouter.post('/request', validate(detailsSchema), async (req, res, next) => {
  try {
    const me = req.user;
    if (me.role === 'superadmin') throw new AppError(400, 'Superadmins change their details directly.');
    if (req.body.fullName === me.full_name && req.body.email === me.email) throw new AppError(400, 'Nothing changed. Edit your name or email first.');
    await assertEmailFree(req.body.email, me.id);
    let created;
    try {
      created = await requests.create({ userId: me.id, fullName: req.body.fullName, email: req.body.email });
    } catch (e) {
      if (e.message === 'ALREADY_PENDING') throw new AppError(409, 'You already have a request waiting for approval. Cancel it first to send a new one.');
      throw e;
    }
    await recordAudit(req, res, {
      action: 'profile_change_requested',
      entityType: 'user',
      entityId: me.id,
      details: { requestId: created.id, old: { fullName: me.full_name, email: me.email }, new: req.body },
    });
    res.status(201).json({ request: created });
  } catch (err) {
    next(err);
  }
});

profileRouter.delete('/request', async (req, res, next) => {
  try {
    const cancelled = await requests.cancelForUser(req.user.id);
    if (!cancelled) throw new AppError(404, 'You have no request waiting.');
    await recordAudit(req, res, { action: 'profile_change_cancelled', entityType: 'user', entityId: req.user.id, details: { requestId: cancelled.id } });
    res.json({ request: cancelled });
  } catch (err) {
    next(err);
  }
});

// ---- Superadmin review ----

profileRequestsRouter.use(requireRole());

profileRequestsRouter.get('/', async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: { created: 'pr.created_at' }, defaultSort: 'created' });
    const { items, totalCount } = await requests.list({
      status: req.query.status || 'pending',
      userId: req.query.userId ? Number(req.query.userId) : null,
      offset: paging.offset,
      pageSize: paging.pageSize,
    });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

async function loadRequest(id) {
  const r = await requests.findById(Number(id));
  if (!r) throw new AppError(404, 'Request not found.');
  return r;
}

profileRequestsRouter.get('/:id', async (req, res, next) => {
  try {
    res.json({ request: await loadRequest(req.params.id) });
  } catch (err) {
    next(err);
  }
});

profileRequestsRouter.post('/:id/approve', async (req, res, next) => {
  try {
    const r = await loadRequest(req.params.id);
    if (r.status !== 'pending') throw new AppError(409, `This request was already ${r.status}.`);
    // Someone may have taken the email since the request was sent.
    const other = await users.findByEmail(r.requested.email);
    if (other && other.id !== r.userId) throw new AppError(409, 'Another account now uses that email. Reject the request, or ask the person to send a new one.');
    const approved = await requests.approve(r.id, req.user.id);
    if (!approved) throw new AppError(409, 'This request was decided a moment ago. Refresh the page.');
    await recordAudit(req, res, {
      action: 'profile_change_approved',
      entityType: 'user',
      entityId: r.userId,
      details: { requestId: r.id, old: r.current, new: r.requested },
    });
    res.json({ request: approved });
  } catch (err) {
    if (err.number === 2601 || err.number === 2627) return next(new AppError(409, 'Another account now uses that email.'));
    next(err);
  }
});

profileRequestsRouter.post(
  '/:id/reject',
  validate(z.object({ reason: z.string().trim().min(1, 'Give a short reason the person will see.').max(500) })),
  async (req, res, next) => {
    try {
      const r = await loadRequest(req.params.id);
      if (r.status !== 'pending') throw new AppError(409, `This request was already ${r.status}.`);
      const rejected = await requests.decide(r.id, { status: 'rejected', reason: req.body.reason, reviewedBy: req.user.id });
      if (!rejected) throw new AppError(409, 'This request was decided a moment ago. Refresh the page.');
      await recordAudit(req, res, { action: 'profile_change_rejected', entityType: 'user', entityId: r.userId, details: { requestId: r.id, reason: req.body.reason } });
      res.json({ request: rejected });
    } catch (err) {
      next(err);
    }
  },
);
