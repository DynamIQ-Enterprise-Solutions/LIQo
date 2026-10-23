import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as stores from '../repos/stores.js';
import * as options from '../repos/options.js';
import * as owners from '../repos/owners.js';
import { resolveScope, assertBranchInScope } from '../utils/scope.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';
import { hoursSchema, STORE_STATUSES } from '../utils/hours.js';

export const storesRouter = Router();

const SORT = { name: 's.name', branch: 'b.name', category: 'c.name', created: 's.created_at', status: 's.is_active' };

const optionalText = (max) => z.string().trim().max(max).nullable().optional().or(z.literal(''));
const blank = (v) => (v === '' || v === undefined ? null : v);

const storeSchema = z.object({
  branchId: z.number().int().positive('Choose a branch.'),
  name: z.string().trim().min(2, 'Store name is required.').max(200),
  categoryId: z.number().int().positive().nullable().optional(),
  logoUrl: optionalText(500),
  description: optionalText(1000),
  openingHours: optionalText(300),
  contactPhone: optionalText(50),
  contactEmail: z.string().trim().email('Enter a valid contact email.').max(255).nullable().optional().or(z.literal('')),
});

const clean = (b) => ({
  branchId: b.branchId,
  name: b.name,
  categoryId: b.categoryId ?? null,
  logoUrl: blank(b.logoUrl),
  description: blank(b.description),
  openingHours: blank(b.openingHours),
  contactPhone: blank(b.contactPhone),
  contactEmail: blank(b.contactEmail),
});

function duplicate(err, next) {
  if (err.number === 2627 || err.number === 2601) return next(new AppError(409, 'That branch already has a store with this name.'));
  if (err.number === 547) return next(new AppError(400, 'The branch or category does not exist.'));
  return next(err);
}

async function checkCategory(branchId, categoryId) {
  if (categoryId == null) return;
  const opt = await options.findById(categoryId);
  if (!opt || opt.kind !== 'store_category' || opt.branchId !== branchId) {
    throw new AppError(400, 'Choose a store category from this branch.');
  }
}

/** Mall admin, supervisor (read), superadmin: stores in scope. Store owner: own stores. */
storesRouter.get('/', async (req, res, next) => {
  try {
    // Mall owners also see the stores of their inactive branches, read-only (owner decision 2026-10-22).
    const scope = await resolveScope(req.user, { includeInactive: true });
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'name' });
    const { items, totalCount } = await stores.list({
      ...paging,
      status: req.query.status,
      branchId: req.query.branchId ? Number(req.query.branchId) : null,
      scopeBranchIds: scope.all ? null : scope.branchIds,
      onlyStoreIds: req.user.role === 'store_owner' ? scope.storeIds : null,
    });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

storesRouter.post('/', requireRole('mall_admin'), validate(storeSchema), async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user);
    assertBranchInScope(scope, req.body.branchId);
    await checkCategory(req.body.branchId, req.body.categoryId ?? null);
    const store = await stores.create(clean(req.body), req.user.id);
    await recordAudit(req, res, { action: 'store_created', entityType: 'store', entityId: store.id, details: { branchId: store.branchId, name: store.name } });
    res.status(201).json({ store });
  } catch (err) {
    duplicate(err, next);
  }
});

async function loadInScope(req, id) {
  const store = await stores.findById(id);
  if (!store) throw new AppError(404, 'Store not found.');
  // includeInactive only widens a mall owner's scope, and owners never write stores.
  const scope = await resolveScope(req.user, { includeInactive: true });
  if (req.user.role === 'store_owner') {
    if (!scope.storeIds.includes(store.id)) throw new AppError(403, 'That store is not assigned to you.');
  } else {
    assertBranchInScope(scope, store.branchId);
  }
  return store;
}

storesRouter.get('/:id', async (req, res, next) => {
  try {
    const store = await loadInScope(req, Number(req.params.id));
    res.json({ store, spaces: await stores.spacesFor(store.id), owners: await owners.ownersForStore(store.id) });
  } catch (err) {
    next(err);
  }
});

storesRouter.put('/:id', requireRole('mall_admin'), validate(storeSchema), async (req, res, next) => {
  try {
    const store = await loadInScope(req, Number(req.params.id));
    if (req.body.branchId !== store.branchId) throw new AppError(400, 'A store cannot be moved to another branch.');
    await checkCategory(store.branchId, req.body.categoryId ?? null);
    const updated = await stores.update(store.id, clean(req.body));
    await recordAudit(req, res, { action: 'store_updated', entityType: 'store', entityId: store.id, details: req.body });
    res.json({ store: updated });
  } catch (err) {
    duplicate(err, next);
  }
});

for (const [verb, active] of [['deactivate', false], ['reactivate', true]]) {
  storesRouter.post(`/:id/${verb}`, requireRole('mall_admin'), async (req, res, next) => {
    try {
      const store = await loadInScope(req, Number(req.params.id));
      const updated = await stores.setActive(store.id, active);
      await recordAudit(req, res, { action: `store_${verb}d`, entityType: 'store', entityId: store.id });
      res.json({ store: updated });
    } catch (err) {
      next(err);
    }
  });
}

// ---- Store ↔ space links (kept apart from map geometry) ----

const spacesSchema = z.object({
  spaceKeys: z.array(z.string().trim().regex(/^[A-Za-z0-9_-]{1,40}$/, 'Space ids may use letters, digits, - and _ only.')).max(100),
});

storesRouter.put('/:id/spaces', requireRole('mall_admin'), validate(spacesSchema), async (req, res, next) => {
  try {
    const store = await loadInScope(req, Number(req.params.id));
    const keys = [...new Set(req.body.spaceKeys)];
    const spaces = await stores.setSpaces(store.id, store.branchId, keys);
    await recordAudit(req, res, { action: 'store_spaces_updated', entityType: 'store', entityId: store.id, details: { spaceKeys: keys } });
    res.json({ spaces });
  } catch (err) {
    next(err);
  }
});

// ---- Round 21: hours and status. The mall admin, or the store owner for their
// own active stores (owner decisions 2026-10-23: a narrow route, audited). ----

const hoursBody = z.object({ hours: hoursSchema.nullable() });
const statusBody = z.object({ status: z.enum(STORE_STATUSES) });

async function loadWritable(req) {
  const store = await loadInScope(req, Number(req.params.id));
  if (req.user.role === 'store_owner' && !store.isActive) throw new AppError(403, 'That store is not active.');
  return store;
}

storesRouter.put('/:id/hours', requireRole('mall_admin', 'store_owner'), validate(hoursBody), async (req, res, next) => {
  try {
    const store = await loadWritable(req);
    const updated = await stores.setHours(store.id, req.body.hours);
    await recordAudit(req, res, { action: 'store_hours_updated', entityType: 'store', entityId: store.id, details: { hours: updated.hours, byRole: req.user.role } });
    res.json({ store: updated });
  } catch (err) {
    next(err);
  }
});

storesRouter.put('/:id/status', requireRole('mall_admin', 'store_owner'), validate(statusBody), async (req, res, next) => {
  try {
    const store = await loadWritable(req);
    const updated = await stores.setStatus(store.id, req.body.status);
    await recordAudit(req, res, { action: 'store_status_changed', entityType: 'store', entityId: store.id, details: { from: store.status, to: updated.status, byRole: req.user.role } });
    res.json({ store: updated });
  } catch (err) {
    next(err);
  }
});
