import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as branches from '../repos/branches.js';
import * as malls from '../repos/malls.js';
import { resolveScope, assertBranchInScope, assertMallInScope } from '../utils/scope.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';
import { hoursSchema } from '../utils/hours.js';
import { resolveMapsLink, MapsLinkError } from '../utils/mapsLink.js';

export const branchesRouter = Router();

const SORT = { name: 'b.name', mall: 'm.name', created: 'b.created_at', status: 'b.is_active' };

const optionalText = (max) => z.string().trim().max(max).nullable().optional().or(z.literal(''));

// A logo must be a real web link (D23).
const webLink = z.string().trim().max(500).url('Enter a full logo link (https://…).').refine((v) => /^https?:\/\//i.test(v), 'Enter a full logo link (https://…).');

const infoSchema = z.object({
  logoUrl: webLink.nullable().optional().or(z.literal('')),
  address: optionalText(500),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  openingHours: optionalText(300),
  contactPhone: optionalText(50),
  contactEmail: z.string().trim().email('Enter a valid contact email.').max(255).nullable().optional().or(z.literal('')),
});

const fullSchema = infoSchema.extend({
  mallId: z.number().int().positive('Choose a mall.'),
  name: z.string().trim().min(2, 'Branch name is required.').max(200),
});

const blankToNull = (v) => (v === '' || v === undefined ? null : v);
const INFO_FIELDS = ['logoUrl', 'address', 'latitude', 'longitude', 'openingHours', 'contactPhone', 'contactEmail'];
/**
 * Branch details from a request. [partial]: only the fields that were sent, so
 * a field left out keeps its value instead of being erased (D22).
 */
const cleanInfo = (b, { partial = false } = {}) => {
  const out = {};
  for (const k of INFO_FIELDS) {
    if (partial && !(k in b)) continue;
    out[k] = blankToNull(b[k]);
  }
  return out;
};

function duplicate(err, next) {
  if (err.number === 2627 || err.number === 2601) return next(new AppError(409, 'That mall already has a branch with this name.'));
  return next(err);
}

branchesRouter.get('/', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'mall' });
    const { items, totalCount } = await branches.list({
      ...paging,
      status: req.query.status,
      mallId: req.query.mallId ? Number(req.query.mallId) : null,
      scopeBranchIds: scope.all ? null : scope.branchIds,
    });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

branchesRouter.post('/', requireRole('superadmin'), validate(fullSchema), async (req, res, next) => {
  try {
    const mall = await malls.findById(req.body.mallId);
    if (!mall) throw new AppError(400, 'That mall does not exist.');
    const branch = await branches.create({ mallId: req.body.mallId, name: req.body.name, ...cleanInfo(req.body) }, req.user.id);
    await recordAudit(req, res, { action: 'branch_created', entityType: 'branch', entityId: branch.id, details: { mallId: mall.id, name: branch.name } });
    res.status(201).json({ branch });
  } catch (err) {
    duplicate(err, next);
  }
});

branchesRouter.get('/:id', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertBranchInScope(scope, req.params.id);
    const branch = await branches.findById(Number(req.params.id));
    if (!branch) throw new AppError(404, 'Branch not found.');
    res.json({ branch });
  } catch (err) {
    next(err);
  }
});

/** What a deactivation would hide: active stores and their owners. */
branchesRouter.get('/:id/impact', requireRole('supervisor'), async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertBranchInScope(scope, req.params.id);
    res.json(await branches.impact(Number(req.params.id)));
  } catch (err) {
    next(err);
  }
});

// Superadmin: everything (name, mall, info). Supervisor / mall admin: info only, inside scope.
branchesRouter.put('/:id', requireRole('supervisor', 'mall_admin'), async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertBranchInScope(scope, id);
    const existing = await branches.findById(id);
    if (!existing) throw new AppError(404, 'Branch not found.');

    let branch;
    if (req.user.role === 'superadmin') {
      const body = fullSchema.parse(req.body);
      assertMallInScope(scope, body.mallId);
      branch = await branches.update(id, { ...existing, mallId: body.mallId, name: body.name, ...cleanInfo(body, { partial: true }) });
    } else {
      const body = infoSchema.parse(req.body);
      branch = await branches.updateInfo(id, cleanInfo(body, { partial: true }));
    }
    await recordAudit(req, res, { action: 'branch_updated', entityType: 'branch', entityId: id, details: req.body });
    res.json({ branch });
  } catch (err) {
    duplicate(err, next);
  }
});

for (const [verb, active] of [['deactivate', false], ['reactivate', true]]) {
  branchesRouter.post(`/:id/${verb}`, requireRole('supervisor'), async (req, res, next) => {
    try {
      const scope = await resolveScope(req.user, { includeInactive: true });
      assertBranchInScope(scope, req.params.id);
      const branch = await branches.setActive(Number(req.params.id), active);
      if (!branch) throw new AppError(404, 'Branch not found.');
      await recordAudit(req, res, { action: `branch_${verb}d`, entityType: 'branch', entityId: branch.id });
      res.json({ branch });
    } catch (err) {
      next(err);
    }
  });
}

// ---- Round 21: hours and the location from a Google Maps link (same people as the branch info). ----

async function loadEditable(req) {
  const id = Number(req.params.id);
  const scope = await resolveScope(req.user, { includeInactive: true });
  assertBranchInScope(scope, id);
  const branch = await branches.findById(id);
  if (!branch) throw new AppError(404, 'Branch not found.');
  return branch;
}

branchesRouter.put('/:id/hours', requireRole('supervisor', 'mall_admin'), validate(z.object({ hours: hoursSchema.nullable() })), async (req, res, next) => {
  try {
    const branch = await loadEditable(req);
    const updated = await branches.setHours(branch.id, req.body.hours);
    await recordAudit(req, res, { action: 'branch_hours_updated', entityType: 'branch', entityId: branch.id, details: { hours: updated.hours } });
    res.json({ branch: updated });
  } catch (err) {
    next(err);
  }
});

const linkBody = z.object({ mapsLink: z.string().trim().min(1, 'Paste a Google Maps link.').max(2000) });

async function readLink(text) {
  try {
    return await resolveMapsLink(text);
  } catch (err) {
    if (err instanceof MapsLinkError) throw new AppError(400, err.message);
    throw err;
  }
}

/** Reads a pasted link without saving it, so the admin can confirm the place. */
branchesRouter.post('/:id/location/check', requireRole('supervisor', 'mall_admin'), validate(linkBody), async (req, res, next) => {
  try {
    await loadEditable(req);
    const found = await readLink(req.body.mapsLink);
    res.locals.audited = true; // a read, nothing changes
    res.json({ placeName: found.placeName });
  } catch (err) {
    next(err);
  }
});

branchesRouter.put('/:id/location', requireRole('supervisor', 'mall_admin'), validate(z.object({ mapsLink: linkBody.shape.mapsLink.nullable() })), async (req, res, next) => {
  try {
    const branch = await loadEditable(req);
    const found = req.body.mapsLink == null ? { mapsLink: null, placeName: null, latitude: null, longitude: null } : await readLink(req.body.mapsLink);
    const updated = await branches.setLocation(branch.id, found);
    await recordAudit(req, res, { action: 'branch_location_updated', entityType: 'branch', entityId: branch.id, details: { mapsLink: found.mapsLink, placeName: found.placeName } });
    res.json({ branch: updated });
  } catch (err) {
    next(err);
  }
});
