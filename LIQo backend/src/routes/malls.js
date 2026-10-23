import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as malls from '../repos/malls.js';
import * as users from '../repos/users.js';
import * as assignments from '../repos/assignments.js';
import { applyReportsToRule } from '../utils/ownership.js';
import { resolveScope, assertMallInScope, assertWholeMallOwner } from '../utils/scope.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';

export const mallsRouter = Router();

const SORT = { name: 'm.name', created: 'm.created_at', status: 'm.is_active' };

const mallSchema = z.object({
  name: z.string().trim().min(2, 'Mall name is required.').max(200),
  logoUrl: z.string().trim().url('Logo must be a valid URL.').max(500).nullable().optional().or(z.literal('')),
});

const clean = (b) => ({ name: b.name, logoUrl: b.logoUrl ? b.logoUrl : null });

mallsRouter.get('/', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'name' });
    const { items, totalCount } = await malls.list({
      ...paging,
      status: req.query.status,
      scopeMallIds: scope.all ? null : scope.mallIds,
      scopeBranchIds: scope.all ? null : scope.branchIds,
    });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

mallsRouter.post('/', requireRole('superadmin'), validate(mallSchema), async (req, res, next) => {
  try {
    const mall = await malls.create({ ...clean(req.body), createdBy: req.user.id });
    await recordAudit(req, res, { action: 'mall_created', entityType: 'mall', entityId: mall.id, details: clean(req.body) });
    res.status(201).json({ mall });
  } catch (err) {
    if (err.number === 2627 || err.number === 2601) return next(new AppError(409, 'A mall with that name already exists.'));
    next(err);
  }
});

mallsRouter.get('/:id', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertMallInScope(scope, req.params.id);
    const mall = await malls.findById(Number(req.params.id), { scopeBranchIds: scope.all ? null : scope.branchIds });
    if (!mall) throw new AppError(404, 'Mall not found.');
    // Whether this person may change the mall (superadmin, or an owner of the whole mall).
    const canManage = scope.all || (scope.wholeMallIds ?? []).includes(mall.id);
    res.json({ mall, canManage });
  } catch (err) {
    next(err);
  }
});

/** What a deactivation would hide: active branches and stores under this mall. */
mallsRouter.get('/:id/impact', requireRole('supervisor'), async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertMallInScope(scope, req.params.id);
    res.json(await malls.impact(Number(req.params.id)));
  } catch (err) {
    next(err);
  }
});

// ---- People on a mall (superadmin only) ----

async function loadMall(id) {
  const mall = await malls.findById(Number(id));
  if (!mall) throw new AppError(404, 'Mall not found.');
  return mall;
}

async function loadRole(id, role, label) {
  const user = await users.findById(Number(id));
  if (!user || user.role !== role) throw new AppError(400, `That account is not a ${label}.`);
  return user;
}

/**
 * Who runs a mall. Superadmin: everyone. Mall owner (read-only, Round 14): the
 * mall's owners, and the admins on the owner's own branches of it.
 */
mallsRouter.get('/:id/people', requireRole('supervisor'), async (req, res, next) => {
  try {
    const mall = await loadMall(req.params.id);
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertMallInScope(scope, mall.id);
    const people = await assignments.mallPeople(mall.id);
    if (!scope.all) people.admins = people.admins.filter((a) => a.branches.some((b) => scope.branchIds.includes(b.id)));
    res.json({ mall, ...people });
  } catch (err) {
    next(err);
  }
});

mallsRouter.post('/:id/owners', requireRole('superadmin'), validate(z.object({ userId: z.number().int().positive() })), async (req, res, next) => {
  try {
    const mall = await loadMall(req.params.id);
    const owner = await loadRole(req.body.userId, 'supervisor', 'mall owner');
    await assignments.addMallOwner(mall.id, owner.id, req.user.id);
    await recordAudit(req, res, { action: 'mall_owner_added', entityType: 'mall', entityId: mall.id, details: { userId: owner.id, email: owner.email } });
    await applyReportsToRule(req, res, 'mall owner added');
    res.json(await assignments.mallPeople(mall.id));
  } catch (err) {
    next(err);
  }
});

mallsRouter.delete('/:id/owners/:userId', requireRole('superadmin'), async (req, res, next) => {
  try {
    const mall = await loadMall(req.params.id);
    const owner = await loadRole(req.params.userId, 'supervisor', 'mall owner');
    await assignments.removeMallOwner(mall.id, owner.id);
    const changes = await applyReportsToRule(req, res, 'mall owner removed');
    // Admins who no longer report to this owner (they moved to the next owner by the rule, or to "No owner").
    const linksCleared = changes.filter((c) => c.from === owner.id).length;
    await recordAudit(req, res, { action: 'mall_owner_removed', entityType: 'mall', entityId: mall.id, details: { userId: owner.id, email: owner.email, linksCleared } });
    res.json({ linksCleared, ...(await assignments.mallPeople(mall.id)) });
  } catch (err) {
    next(err);
  }
});

const adminSchema = z
  .object({
    branchIds: z.array(z.number().int().positive()).min(1, 'Choose the branch.').max(1, 'A mall admin manages exactly one branch.'),
  })
  .strict('Who an admin reports to is set automatically from branch ownership.');

/** Sets an admin's branch inside this mall; who they report to follows the ownership rule. */
mallsRouter.put('/:id/admins/:userId', requireRole('superadmin'), validate(adminSchema), async (req, res, next) => {
  try {
    const mall = await loadMall(req.params.id);
    const admin = await loadRole(req.params.userId, 'mall_admin', 'mall admin');
    let result;
    try {
      result = await assignments.setMallAdminBranches(mall.id, admin.id, req.body.branchIds, req.user.id);
    } catch (e) {
      if (e.message === 'BRANCH_NOT_IN_MALL') throw new AppError(400, 'That branch does not belong to this mall.');
      if (e.message === 'ALREADY_ELSEWHERE') throw new AppError(409, 'This admin already manages a branch in another mall. Remove them there first.');
      if (e.message === assignments.ONE_BRANCH) throw new AppError(400, 'A mall admin manages exactly one branch.');
      throw e;
    }
    await recordAudit(req, res, {
      action: 'mall_admin_assignments_updated',
      entityType: 'user',
      entityId: admin.id,
      details: { mallId: mall.id, branchIds: req.body.branchIds },
    });
    await applyReportsToRule(req, res, 'admin placed');
    res.json({ user: users.toPublic(await users.findById(admin.id)), ...result });
  } catch (err) {
    if (err.number === 547) return next(new AppError(400, 'One of the branches does not exist.'));
    next(err);
  }
});

mallsRouter.delete('/:id/admins/:userId', requireRole('superadmin'), async (req, res, next) => {
  try {
    const mall = await loadMall(req.params.id);
    const admin = await loadRole(req.params.userId, 'mall_admin', 'mall admin');
    const result = await assignments.removeMallAdmin(mall.id, admin.id, req.user.id);
    await recordAudit(req, res, { action: 'mall_admin_removed_from_mall', entityType: 'user', entityId: admin.id, details: { mallId: mall.id } });
    await applyReportsToRule(req, res, 'admin removed from mall');
    res.json({ user: users.toPublic(await users.findById(admin.id)), ...result });
  } catch (err) {
    next(err);
  }
});

mallsRouter.put('/:id', requireRole('supervisor'), validate(mallSchema), async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user, { includeInactive: true });
    assertMallInScope(scope, req.params.id);
    assertWholeMallOwner(scope, req.params.id);
    const mall = await malls.update(Number(req.params.id), clean(req.body));
    if (!mall) throw new AppError(404, 'Mall not found.');
    await recordAudit(req, res, { action: 'mall_updated', entityType: 'mall', entityId: mall.id, details: clean(req.body) });
    res.json({ mall });
  } catch (err) {
    if (err.number === 2627 || err.number === 2601) return next(new AppError(409, 'A mall with that name already exists.'));
    next(err);
  }
});

for (const [verb, active] of [['deactivate', false], ['reactivate', true]]) {
  mallsRouter.post(`/:id/${verb}`, requireRole('supervisor'), async (req, res, next) => {
    try {
      const scope = await resolveScope(req.user, { includeInactive: true });
      assertMallInScope(scope, req.params.id);
      assertWholeMallOwner(scope, req.params.id);
      const mall = await malls.setActive(Number(req.params.id), active);
      if (!mall) throw new AppError(404, 'Mall not found.');
      await recordAudit(req, res, { action: `mall_${verb}d`, entityType: 'mall', entityId: mall.id });
      res.json({ mall });
    } catch (err) {
      next(err);
    }
  });
}
