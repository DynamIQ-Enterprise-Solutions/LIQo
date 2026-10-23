// AI credits per mall admin (Round 19, owner decisions 2026-10-23).
//   Superadmin:  GET /overview, GET /history, POST /:userId/adjust,
//                GET /requests, GET /requests/:id, POST /requests/:id/approve|decline
//   Mall owner:  GET /overview (their admins, read only; no wallet, no requests)
//   Mall admin:  GET /mine, POST /requests, DELETE /requests/mine
import { Router } from 'express';
import { z } from 'zod';
import { requireRole } from '../middleware/requireRole.js';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as credits from '../repos/credits.js';
import * as settings from '../repos/settings.js';
import { walletSplit, round4 } from '../ai/credits.js';
import { give, take, readWallet } from '../ai/creditOps.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';

export const creditsRouter = Router();

const daysOf = (q) => ([7, 30, 90].includes(Number(q.days)) ? Number(q.days) : 30);
const amount = z.coerce.number().positive('Enter more than 0 credits.').max(100000).transform(round4);

/** The wallet split, admins, daily use and open requests (superadmin); an owner's admins (mall owner). */
creditsRouter.get('/overview', requireRole('supervisor'), async (req, res, next) => {
  try {
    const days = daysOf(req.query);
    const cap = await settings.getNumber('ai_credit_cap');
    if (req.user.role === 'supervisor') {
      const admins = await credits.adminRows({ days, reportsTo: req.user.id });
      const usage = await credits.usageSeries({ days, userIds: admins.map((a) => a.id) });
      return res.json({ days, cap, wallet: null, admins, usage, requests: null });
    }
    const [wallet, given, admins, usage, requests] = await Promise.all([
      readWallet(),
      credits.givenTotal(),
      credits.adminRows({ days }),
      credits.usageSeries({ days }),
      credits.listRequests({ status: 'pending', offset: 0, pageSize: 5 }),
    ]);
    res.json({
      days,
      cap,
      // The last top-up (kept by GET /ai/status) lets the bar show what was used since.
      wallet: { ...walletSplit({ wallet, given, used: usage.total }), full: Number(await settings.getText('ai_wallet_full')) || null },
      admins,
      usage,
      requests: { waiting: requests.totalCount, items: requests.items },
    });
  } catch (err) {
    next(err);
  }
});

/** Every credit change, newest first. */
creditsRouter.get('/history', requireRole(), async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: { created: 'l.id' }, defaultSort: 'created' });
    const { items, totalCount } = await credits.history({
      userId: req.query.userId ? Number(req.query.userId) : null,
      offset: paging.offset,
      pageSize: paging.pageSize,
    });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

/** The signed-in mall admin's own credits. */
creditsRouter.get('/mine', requireRole('mall_admin'), async (req, res, next) => {
  try {
    const [mine, cap, avg, request] = await Promise.all([
      credits.balanceOf(req.user.id),
      settings.getNumber('ai_credit_cap'),
      credits.avgCost(),
      credits.latestRequestFor(req.user.id),
    ]);
    res.json({ balance: mine.balance, full: mine.full, cap, avgCost: avg, request });
  } catch (err) {
    next(err);
  }
});

// ---- Requests ----

creditsRouter.post('/requests', requireRole('mall_admin'), validate(z.object({ amount })), async (req, res, next) => {
  try {
    if (req.user.role !== 'mall_admin') throw new AppError(400, 'Only mall admins ask for AI credits.');
    const cap = await settings.getNumber('ai_credit_cap');
    const { balance } = await credits.balanceOf(req.user.id);
    const room = round4(cap - Math.max(0, balance));
    if (room <= 0) throw new AppError(409, `You already have the most allowed (${cap} credits).`);
    if (req.body.amount > room) throw new AppError(400, `You can ask for at most ${room} credits (the most per admin is ${cap}).`);
    let created;
    try {
      created = await credits.createRequest(req.user.id, req.body.amount);
    } catch (e) {
      if (e.message === 'ALREADY_PENDING') throw new AppError(409, 'You already have a request waiting. Cancel it first to ask again.');
      throw e;
    }
    await recordAudit(req, res, { action: 'ai_credit_requested', entityType: 'user', entityId: req.user.id, details: { requestId: created.id, amount: created.amount } });
    res.status(201).json({ request: created });
  } catch (err) {
    next(err);
  }
});

creditsRouter.delete('/requests/mine', requireRole('mall_admin'), async (req, res, next) => {
  try {
    const cancelled = await credits.cancelOpenRequest(req.user.id);
    if (!cancelled) throw new AppError(404, 'You have no request waiting.');
    await recordAudit(req, res, { action: 'ai_credit_request_cancelled', entityType: 'user', entityId: req.user.id, details: { requestId: cancelled.id } });
    res.json({ request: cancelled });
  } catch (err) {
    next(err);
  }
});

creditsRouter.get('/requests', requireRole(), async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: { created: 'r.created_at' }, defaultSort: 'created' });
    const status = ['pending', 'approved', 'declined', 'cancelled', 'all'].includes(req.query.status) ? req.query.status : 'pending';
    const { items, totalCount } = await credits.listRequests({ status, offset: paging.offset, pageSize: paging.pageSize });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

async function loadRequest(id) {
  const r = await credits.findRequest(Number(id));
  if (!r) throw new AppError(404, 'Request not found.');
  return r;
}

/** One request, with what the superadmin needs to decide: the free part and the room under the cap. */
creditsRouter.get('/requests/:id', requireRole(), async (req, res, next) => {
  try {
    const r = await loadRequest(req.params.id);
    const [wallet, given, cap] = await Promise.all([readWallet(), credits.givenTotal(), settings.getNumber('ai_credit_cap')]);
    const split = walletSplit({ wallet, given });
    res.json({ request: r, limits: { free: split.free, overGiven: split.overGiven, cap, room: round4(Math.max(0, cap - Math.max(0, r.balance))) } });
  } catch (err) {
    next(err);
  }
});

creditsRouter.post('/requests/:id/approve', requireRole(), validate(z.object({ amount: amount.optional() })), async (req, res, next) => {
  try {
    const r = await loadRequest(req.params.id);
    if (r.status !== 'pending') throw new AppError(409, `This request was already ${r.status}.`);
    const value = req.body.amount ?? r.amount;
    if (value > r.amount) throw new AppError(400, `Give at most what was asked (${r.amount}).`);
    const balance = await give({
      userId: r.userId,
      amount: value,
      actorId: req.user.id,
      kind: 'request',
      requestId: r.id,
      beforeChange: async (tx) => {
        if (!(await credits.decideRequest(tx, r.id, { status: 'approved', amount: value, by: req.user.id }))) {
          throw new AppError(409, 'This request was decided a moment ago. Refresh the page.');
        }
      },
    });
    await recordAudit(req, res, {
      action: 'ai_credit_request_approved',
      entityType: 'user',
      entityId: r.userId,
      details: { requestId: r.id, asked: r.amount, given: value, balanceAfter: balance },
    });
    res.json({ request: await credits.findRequest(r.id) });
  } catch (err) {
    next(err);
  }
});

creditsRouter.post(
  '/requests/:id/decline',
  requireRole(),
  validate(z.object({ reason: z.string().trim().max(300).optional() })),
  async (req, res, next) => {
    try {
      const r = await loadRequest(req.params.id);
      if (r.status !== 'pending') throw new AppError(409, `This request was already ${r.status}.`);
      const ok = await credits.withCreditsLock((tx) => credits.decideRequest(tx, r.id, { status: 'declined', reason: req.body.reason || null, by: req.user.id }));
      if (!ok) throw new AppError(409, 'This request was decided a moment ago. Refresh the page.');
      await recordAudit(req, res, { action: 'ai_credit_request_declined', entityType: 'user', entityId: r.userId, details: { requestId: r.id, reason: req.body.reason || null } });
      res.json({ request: await credits.findRequest(r.id) });
    } catch (err) {
      next(err);
    }
  },
);

// ---- Giving and taking back (superadmin) ----

creditsRouter.post(
  '/:userId/adjust',
  requireRole(),
  validate(z.object({ delta: z.coerce.number().refine((v) => v !== 0, 'Enter an amount other than 0.').transform(round4), note: z.string().trim().max(200).optional() })),
  async (req, res, next) => {
    try {
      const userId = Number(req.params.userId);
      const { delta } = req.body;
      const note = req.body.note || null;
      const balance = delta > 0 ? await give({ userId, amount: delta, actorId: req.user.id, note }) : await take({ userId, amount: -delta, actorId: req.user.id, note });
      await recordAudit(req, res, {
        action: delta > 0 ? 'ai_credits_granted' : 'ai_credits_removed',
        entityType: 'user',
        entityId: userId,
        details: { delta, balanceAfter: balance, note },
      });
      res.json({ balance });
    } catch (err) {
      next(err);
    }
  },
);
