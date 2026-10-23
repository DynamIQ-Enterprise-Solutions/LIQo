import { Router } from 'express';
import * as stores from '../repos/stores.js';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as announcements from '../repos/announcements.js';
import * as settings from '../repos/settings.js';
import { resolveScope } from '../utils/scope.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';
import { todayDateOnly } from '../utils/dates.js';

export const announcementsRouter = Router();

const SORT = { created: 'a.created_at', start: 'a.starts_on', end: 'a.ends_on', title: 'a.title', status: 'a.status' };
const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use the format yyyy-mm-dd.');

const baseSchema = z.object({
  title: z.string().trim().min(2, 'Title is required.').max(200),
  body: z.string().trim().min(1, 'Message is required.').max(5000),
  imageUrl: z.string().trim().max(500).url('Enter a full image link (https://…).').refine((v) => /^https?:\/\//i.test(v), 'Enter a full image link (https://…).').nullable().optional().or(z.literal('')),
  startsOn: dateOnly,
  endsOn: dateOnly,
});

const managerSchema = baseSchema.extend({
  branchIds: z.array(z.number().int().positive()).min(1, 'Choose at least one branch.').max(200),
});

const ownerSchema = baseSchema.extend({
  storeId: z.number().int().positive('Choose a store.'),
});

async function visibilityFor(user) {
  const scope = await resolveScope(user);
  if (scope.all) return { all: true };
  if (user.role === 'store_owner') return { ownerId: user.id, branchIds: scope.branchIds };
  return { branchIds: scope.branchIds };
}

function checkDates(startsOn, endsOn, { isNew = false } = {}) {
  if (endsOn < startsOn) throw new AppError(400, 'End date must be on or after the start date.');
  // A new announcement cannot be over before it starts showing (D23).
  if (isNew && endsOn < todayDateOnly()) throw new AppError(400, 'The end date has already passed.');
}

/**
 * What a manager may do with an announcement (owner decision 2026-10-22,
 * "their part only"): anyone whose branches it targets may view it; only its
 * author, someone whose scope covers all its targets, or a superadmin may
 * change or delete it; others may only take it off their own branches. Mall
 * owners never change store-owner submissions (mall admins review them).
 */
async function managerAccess(user, ann) {
  const scope = await resolveScope(user);
  if (scope.all) return { scope, view: true, change: true, detach: true, mine: ann.branches.map((b) => b.id), shared: false };
  const mine = ann.branches.filter((b) => scope.branchIds.includes(b.id)).map((b) => b.id);
  const shared = mine.length < ann.branches.length;
  const ownerOnSubmission = user.role === 'supervisor' && ann.createdRole === 'store_owner';
  return {
    scope,
    view: mine.length > 0,
    change: !ownerOnSubmission && (ann.createdBy === user.id || !shared),
    detach: !ownerOnSubmission && shared && mine.length > 0,
    mine,
    shared,
  };
}

async function assertManagerScope(user, ann) {
  const access = await managerAccess(user, ann);
  if (!access.view) throw new AppError(403, 'That announcement is outside your assigned scope.');
  return access;
}

/** What a person is shown: only their own branches in the target list, plus what they may do. */
async function present(user, ann) {
  if (user.role === 'store_owner') return ann;
  const access = await managerAccess(user, ann);
  if (access.scope.all) return { ...ann, sharedBeyondScope: false, canChange: true, canDetach: false };
  return {
    ...ann,
    branches: ann.branches.filter((b) => access.mine.includes(b.id)),
    sharedBeyondScope: access.shared,
    canChange: access.change,
    canDetach: access.detach,
  };
}

announcementsRouter.get('/', async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'created' });
    const { items, totalCount } = await announcements.list({
      ...paging,
      sortOrder: req.query.sortOrder ? paging.sortOrder : 'DESC',
      status: req.query.status || null,
      live: req.query.live || null,
      visibility: await visibilityFor(req.user),
    });
    const shown = [];
    for (const a of items) shown.push(await present(req.user, a));
    res.json(pageEnvelope(shown, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

announcementsRouter.get('/defaults', async (req, res, next) => {
  try {
    const days = await settings.getNumber('default_announcement_days');
    const start = new Date();
    const end = new Date(start.getTime() + (days - 1) * 86400000);
    const fmt = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    res.json({ startsOn: fmt(start), endsOn: fmt(end), days });
  } catch (err) {
    next(err);
  }
});

announcementsRouter.get('/:id', async (req, res, next) => {
  try {
    const ann = await announcements.findById(Number(req.params.id));
    if (!ann) throw new AppError(404, 'Announcement not found.');
    if (req.user.role === 'store_owner') {
      if (ann.createdBy !== req.user.id && ann.status !== 'approved') throw new AppError(403, 'You cannot view that announcement.');
    } else {
      await assertManagerScope(req.user, ann);
    }
    res.json({ announcement: await present(req.user, ann) });
  } catch (err) {
    next(err);
  }
});

// Supervisors and mall admins post directly (approved). Store owners submit for review (pending).
announcementsRouter.post('/', async (req, res, next) => {
  try {
    const role = req.user.role;
    let created;

    if (role === 'store_owner') {
      const body = ownerSchema.parse(req.body);
      const ownedBranchId = await stores.branchOfOwnedActiveStore(req.user.id, body.storeId);
      if (ownedBranchId == null) throw new AppError(403, 'That store is not assigned to you.');
      checkDates(body.startsOn, body.endsOn, { isNew: true });
      created = await announcements.create({
        ...body,
        imageUrl: body.imageUrl || null,
        status: 'pending',
        storeId: body.storeId,
        createdBy: req.user.id,
        createdRole: role,
        branchIds: [ownedBranchId],
      });
      await recordAudit(req, res, { action: 'announcement_submitted', entityType: 'announcement', entityId: created.id, details: { storeId: body.storeId } });
      return res.status(201).json({ announcement: created });
    }

    if (!['superadmin', 'supervisor', 'mall_admin'].includes(role)) throw new AppError(403, 'You do not have access to this action.');
    const body = managerSchema.parse(req.body);
    const scope = await resolveScope(req.user);
    if (!scope.all) {
      const outside = body.branchIds.filter((id) => !scope.branchIds.includes(id));
      if (outside.length) throw new AppError(403, 'Some target branches are outside your assigned scope.');
    }
    checkDates(body.startsOn, body.endsOn, { isNew: true });
    created = await announcements.create({
      ...body,
      imageUrl: body.imageUrl || null,
      status: 'approved',
      storeId: null,
      createdBy: req.user.id,
      createdRole: role,
      branchIds: body.branchIds,
    });
    await recordAudit(req, res, { action: 'announcement_published', entityType: 'announcement', entityId: created.id, details: { branchIds: body.branchIds } });
    res.status(201).json({ announcement: await present(req.user, created) });
  } catch (err) {
    if (err.number === 547) return next(new AppError(400, 'One of the target branches does not exist.'));
    next(err);
  }
});

announcementsRouter.put('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const ann = await announcements.findById(id);
    if (!ann) throw new AppError(404, 'Announcement not found.');

    let updated;
    if (req.user.role === 'store_owner') {
      if (ann.createdBy !== req.user.id) throw new AppError(403, 'You can only edit your own announcements.');
      const body = baseSchema.parse(req.body);
      checkDates(body.startsOn, body.endsOn);
      // An edited submission goes back for review.
      updated = await announcements.update(id, { ...body, imageUrl: body.imageUrl || null, status: 'pending' });
    } else {
      const access = await assertManagerScope(req.user, ann);
      if (!access.change) {
        throw new AppError(
          403,
          req.user.role === 'supervisor' && ann.createdRole === 'store_owner'
            ? 'Store-owner submissions are reviewed and edited by mall admins.'
            : 'This announcement also reaches other branches; only its author can change it. You can remove it from your branches.',
        );
      }
      const body = managerSchema.partial({ branchIds: true }).parse(req.body);
      checkDates(body.startsOn, body.endsOn);
      if (body.branchIds) {
        const scope = await resolveScope(req.user);
        if (!scope.all && body.branchIds.some((b) => !scope.branchIds.includes(b))) {
          throw new AppError(403, 'Some target branches are outside your assigned scope.');
        }
      }
      updated = await announcements.update(id, { ...body, imageUrl: body.imageUrl || null });
    }
    await recordAudit(req, res, { action: 'announcement_updated', entityType: 'announcement', entityId: id, details: req.body });
    res.json({ announcement: await present(req.user, updated) });
  } catch (err) {
    next(err);
  }
});

const reviewSchema = z.object({ reason: z.string().trim().max(500).optional() });

for (const [verb, status] of [['approve', 'approved'], ['reject', 'rejected']]) {
  // Mall admins review store-owner submissions (US-022; owner decision 2026-10-22). Superadmin passes requireRole.
  announcementsRouter.post(`/:id/${verb}`, requireRole('mall_admin'), validate(reviewSchema), async (req, res, next) => {
    try {
      const id = Number(req.params.id);
      const ann = await announcements.findById(id);
      if (!ann) throw new AppError(404, 'Announcement not found.');
      if (ann.status !== 'pending') throw new AppError(409, `This announcement was already ${ann.status}.`);
      await assertManagerScope(req.user, ann);
      if (status === 'rejected' && !req.body.reason) throw new AppError(400, 'Give a short reason for the rejection.');
      const updated = await announcements.review(id, { status, reviewedBy: req.user.id, reason: req.body.reason });
      await recordAudit(req, res, { action: `announcement_${status}`, entityType: 'announcement', entityId: id, details: { reason: req.body.reason } });
      res.json({ announcement: await present(req.user, updated) });
    } catch (err) {
      next(err);
    }
  });
}

announcementsRouter.delete('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const ann = await announcements.findById(id);
    if (!ann) throw new AppError(404, 'Announcement not found.');
    if (req.user.role === 'store_owner') {
      if (ann.createdBy !== req.user.id || ann.status === 'approved') {
        throw new AppError(403, 'Only your own pending or rejected submissions can be deleted.');
      }
    } else {
      const access = await assertManagerScope(req.user, ann);
      if (!access.change) {
        // Shared beyond their scope: it only leaves their own branches.
        if (!access.detach) throw new AppError(403, 'Store-owner submissions are reviewed and removed by mall admins.');
        await announcements.removeBranches(id, access.mine);
        await recordAudit(req, res, { action: 'announcement_detached', entityType: 'announcement', entityId: id, details: { title: ann.title, branchIds: access.mine } });
        return res.status(200).json({ detached: access.mine });
      }
    }
    await announcements.remove(id);
    await recordAudit(req, res, { action: 'announcement_deleted', entityType: 'announcement', entityId: id, details: { title: ann.title } });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

export const todayForTests = todayDateOnly;
