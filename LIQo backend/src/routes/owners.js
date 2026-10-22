import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as users from '../repos/users.js';
import * as owners from '../repos/owners.js';
import * as stores from '../repos/stores.js';
import { resolveScope, assertBranchInScope } from '../utils/scope.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';
import { hashPassword, generateTempPassword } from '../utils/password.js';

export const ownersRouter = Router();

const SORT = { name: 'u.full_name', email: 'u.email', created: 'u.created_at', lastLogin: 'u.last_login_at' };

async function storeInScope(req, storeId) {
  const store = await stores.findById(storeId);
  if (!store) throw new AppError(404, 'Store not found.');
  assertBranchInScope(await resolveScope(req.user), store.branchId);
  return store;
}

/** A mall admin may manage an owner only if the owner has a store inside the admin's scope. */
async function loadOwnerInScope(req, userId) {
  const user = await users.findById(userId);
  if (!user || user.role !== 'store_owner') throw new AppError(404, 'Store owner not found.');
  const scope = await resolveScope(req.user);
  if (!scope.all) {
    const list = await owners.storesForOwner(user.id);
    // An owner with no stores at all (just removed from the last one) may be picked up by any mall admin.
    if (list.length > 0 && !list.some((s) => scope.branchIds.includes(s.branchId))) {
      throw new AppError(403, 'That store owner is outside your assigned scope.');
    }
  }
  return user;
}

ownersRouter.get('/', requireRole('mall_admin', 'supervisor'), async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user);
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'name' });
    const { items, totalCount } = await owners.list({ ...paging, status: req.query.status, scopeBranchIds: scope.all ? null : scope.branchIds });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

// Create an owner through a store assignment. If the email already belongs to an
// active store owner, the store is added to that owner instead. An inactive store
// owner is refused: reactivate them first (owner decision 2026-10-22).
const createSchema = z.object({
  email: z.string().trim().toLowerCase().email('Enter a valid email address.'),
  fullName: z.string().trim().min(2, 'Full name is required.').max(200),
  storeId: z.number().int().positive('Choose a store.'),
});

ownersRouter.post('/', requireRole('mall_admin'), validate(createSchema), async (req, res, next) => {
  try {
    const store = await storeInScope(req, req.body.storeId);
    const existing = await users.findByEmail(req.body.email);
    let tempPassword = null;
    let userId;

    if (existing) {
      if (existing.role !== 'store_owner') throw new AppError(409, 'That email belongs to an account with a different role.');
      if (!existing.is_active) {
        throw new AppError(409, 'This store owner is inactive. Reactivate them from Store owners first, then add the store there.');
      }
      userId = existing.id;
    } else {
      tempPassword = generateTempPassword();
      userId = await users.create({
        email: req.body.email,
        fullName: req.body.fullName,
        role: 'store_owner',
        passwordHash: await hashPassword(tempPassword),
        createdBy: req.user.id,
        mustChange: true,
      });
    }
    await owners.assign(userId, store.id, req.user.id);
    await recordAudit(req, res, { action: existing ? 'store_owner_assigned' : 'store_owner_created', entityType: 'user', entityId: userId, details: { storeId: store.id } });
    const user = users.toPublic(await users.findById(userId));
    res.status(201).json({ user: { ...user, stores: await owners.storesForOwner(userId) }, tempPassword });
  } catch (err) {
    next(err);
  }
});

ownersRouter.get('/:id', requireRole('mall_admin', 'supervisor'), async (req, res, next) => {
  try {
    const user = await loadOwnerInScope(req, Number(req.params.id));
    res.json({ user: { ...users.toPublic(user), stores: await owners.storesForOwner(user.id) } });
  } catch (err) {
    next(err);
  }
});

const storeIdSchema = z.object({ storeId: z.number().int().positive('Choose a store.') });

ownersRouter.post('/:id/assign', requireRole('mall_admin'), validate(storeIdSchema), async (req, res, next) => {
  try {
    const user = await loadOwnerInScope(req, Number(req.params.id));
    const store = await storeInScope(req, req.body.storeId);
    await owners.assign(user.id, store.id, req.user.id);
    if (!user.is_active) await users.setActive(user.id, true);
    await recordAudit(req, res, { action: 'store_owner_assigned', entityType: 'user', entityId: user.id, details: { storeId: store.id } });
    res.json({ user: { ...users.toPublic(await users.findById(user.id)), stores: await owners.storesForOwner(user.id) } });
  } catch (err) {
    next(err);
  }
});

ownersRouter.post('/:id/unassign', requireRole('mall_admin'), validate(storeIdSchema), async (req, res, next) => {
  try {
    const user = await loadOwnerInScope(req, Number(req.params.id));
    const store = await storeInScope(req, req.body.storeId);
    await owners.unassign(user.id, store.id);
    const remaining = await owners.storesForOwner(user.id);
    let deactivated = false;
    if (remaining.length === 0) {
      // US-020: an owner with no stores left is deactivated automatically.
      await users.setActive(user.id, false);
      deactivated = true;
    }
    await recordAudit(req, res, { action: 'store_owner_unassigned', entityType: 'user', entityId: user.id, details: { storeId: store.id, deactivated } });
    res.json({ user: { ...users.toPublic(await users.findById(user.id)), stores: remaining }, deactivated });
  } catch (err) {
    next(err);
  }
});

const profileSchema = z.object({
  fullName: z.string().trim().min(2, 'Full name is required.').max(200),
  email: z.string().trim().toLowerCase().email('Enter a valid email address.'),
});

ownersRouter.put('/:id', requireRole('mall_admin'), validate(profileSchema), async (req, res, next) => {
  try {
    const user = await loadOwnerInScope(req, Number(req.params.id));
    const other = await users.findByEmail(req.body.email);
    if (other && other.id !== user.id) throw new AppError(409, 'Another account already uses that email.');
    const updated = await users.updateProfile(user.id, req.body);
    await recordAudit(req, res, { action: 'account_updated', entityType: 'user', entityId: user.id, details: req.body });
    res.json({ user: { ...users.toPublic(updated), stores: await owners.storesForOwner(user.id) } });
  } catch (err) {
    next(err);
  }
});

ownersRouter.post('/:id/reset-password', requireRole('mall_admin'), async (req, res, next) => {
  try {
    const user = await loadOwnerInScope(req, Number(req.params.id));
    const tempPassword = generateTempPassword();
    await users.setPassword(user.id, await hashPassword(tempPassword), { mustChange: true });
    await recordAudit(req, res, { action: 'password_reset_by_admin', entityType: 'user', entityId: user.id });
    res.json({ tempPassword });
  } catch (err) {
    next(err);
  }
});

for (const [verb, active] of [['deactivate', false], ['reactivate', true]]) {
  ownersRouter.post(`/:id/${verb}`, requireRole('mall_admin'), async (req, res, next) => {
    try {
      const user = await loadOwnerInScope(req, Number(req.params.id));
      const updated = await users.setActive(user.id, active);
      await recordAudit(req, res, { action: `account_${verb}d`, entityType: 'user', entityId: user.id });
      res.json({ user: { ...users.toPublic(updated), stores: await owners.storesForOwner(user.id) } });
    } catch (err) {
      next(err);
    }
  });
}
