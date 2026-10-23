import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as options from '../repos/options.js';
import { resolveScope, assertBranchInScope } from '../utils/scope.js';
import { APP_CATEGORIES } from '../utils/hours.js';

export const optionsRouter = Router();

const kindSchema = z.enum(['store_category', 'unit_type', 'floor_label'], { errorMap: () => ({ message: 'Unknown option kind.' }) });

const createSchema = z.object({
  branchId: z.number().int().positive('Choose a branch.'),
  kind: kindSchema,
  name: z.string().trim().min(1, 'Name is required.').max(100),
  sortOrder: z.number().int().min(0).max(9999).optional(),
});

const updateSchema = z.object({
  name: z.string().trim().min(1, 'Name is required.').max(100),
  sortOrder: z.number().int().min(0).max(9999).optional(),
});

function duplicate(err, next) {
  if (err.number === 2627 || err.number === 2601) return next(new AppError(409, 'That option already exists for this branch.'));
  return next(err);
}

async function loadInScope(req, id) {
  const opt = await options.findById(id);
  if (!opt) throw new AppError(404, 'Option not found.');
  assertBranchInScope(await resolveScope(req.user), opt.branchId);
  return opt;
}

// GET /options?branchId=&kind=&includeInactive=
optionsRouter.get('/', async (req, res, next) => {
  try {
    const branchId = Number(req.query.branchId);
    if (!branchId) throw new AppError(400, 'branchId is required.');
    assertBranchInScope(await resolveScope(req.user), branchId);
    const kind = req.query.kind ? kindSchema.parse(req.query.kind) : null;
    res.json({ items: await options.list({ branchId, kind, includeInactive: req.query.includeInactive === 'true' }) });
  } catch (err) {
    next(err);
  }
});

optionsRouter.post('/', requireRole('mall_admin'), validate(createSchema), async (req, res, next) => {
  try {
    assertBranchInScope(await resolveScope(req.user), req.body.branchId);
    const opt = await options.create(req.body);
    await recordAudit(req, res, { action: 'option_created', entityType: 'branch_option', entityId: opt.id, details: req.body });
    res.status(201).json({ option: opt });
  } catch (err) {
    duplicate(err, next);
  }
});

optionsRouter.put('/:id', requireRole('mall_admin'), validate(updateSchema), async (req, res, next) => {
  try {
    const opt = await loadInScope(req, Number(req.params.id));
    const updated = await options.update(opt.id, req.body);
    await recordAudit(req, res, { action: 'option_updated', entityType: 'branch_option', entityId: opt.id, details: req.body });
    res.json({ option: updated });
  } catch (err) {
    duplicate(err, next);
  }
});

for (const [verb, active] of [['deactivate', false], ['reactivate', true]]) {
  optionsRouter.post(`/:id/${verb}`, requireRole('mall_admin'), async (req, res, next) => {
    try {
      const opt = await loadInScope(req, Number(req.params.id));
      const updated = await options.setActive(opt.id, active);
      await recordAudit(req, res, { action: `option_${verb}d`, entityType: 'branch_option', entityId: opt.id });
      res.json({ option: updated });
    } catch (err) {
      next(err);
    }
  });
}

// Delete only when nothing uses it; otherwise the caller should deactivate.
optionsRouter.delete('/:id', requireRole('mall_admin'), async (req, res, next) => {
  try {
    const opt = await loadInScope(req, Number(req.params.id));
    if (opt.inUse > 0) {
      throw new AppError(409, `This option is used by ${opt.inUse} store${opt.inUse === 1 ? '' : 's'}. Deactivate it instead.`);
    }
    await options.remove(opt.id);
    await recordAudit(req, res, { action: 'option_deleted', entityType: 'branch_option', entityId: opt.id, details: { name: opt.name, kind: opt.kind } });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

/** One option value, for its detail page. */
optionsRouter.get('/:id', async (req, res, next) => {
  try {
    const opt = await options.findById(Number(req.params.id));
    if (!opt) throw new AppError(404, 'Option not found.');
    assertBranchInScope(await resolveScope(req.user), opt.branchId);
    res.json({ option: opt });
  } catch (err) {
    next(err);
  }
});

// Round 21: the shopper app's category for a store category (owner decision 2026-10-23; default Other).
optionsRouter.put('/:id/app-category', requireRole('mall_admin'), validate(z.object({ appCategory: z.enum(APP_CATEGORIES) })), async (req, res, next) => {
  try {
    const opt = await loadInScope(req, Number(req.params.id));
    if (opt.kind !== 'store_category') throw new AppError(400, 'Only store categories have an App category.');
    const updated = await options.setAppCategory(opt.id, req.body.appCategory);
    await recordAudit(req, res, { action: 'option_app_category_set', entityType: 'branch_option', entityId: opt.id, details: { from: opt.appCategory, to: updated.appCategory } });
    res.json({ option: updated });
  } catch (err) {
    next(err);
  }
});
