import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as users from '../repos/users.js';
import * as assignments from '../repos/assignments.js';
import * as owners from '../repos/owners.js';
import * as requests from '../repos/profileRequests.js';
import { resolveScope, assertBranchInScope } from '../utils/scope.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';
import { hashPassword, generateTempPassword } from '../utils/password.js';
import { applyReportsToRule } from '../utils/ownership.js';
import * as creditOps from '../ai/creditOps.js';

export const accountsRouter = Router();

const SORT = { email: 'u.email', name: 'u.full_name', role: 'u.role', created: 'u.created_at', lastLogin: 'u.last_login_at' };

/**
 * Who may the caller manage? Superadmin: everyone; another superadmin only for
 * viewing, deactivating, reactivating and resetting the password
 * ([otherSuperadmin] true; owner decision 2026-10-22). Mall owner: the admins
 * that report to them.
 */
async function loadManageable(req, id, { otherSuperadmin = false } = {}) {
  const target = await users.findById(id);
  if (!target) throw new AppError(404, 'Account not found.');
  if (req.user.role === 'superadmin') {
    if (target.role === 'superadmin' && target.id !== req.user.id && !otherSuperadmin) {
      throw new AppError(403, "Another superadmin's name and email cannot be changed here.");
    }
    return target;
  }
  if (req.user.role === 'supervisor') {
    if (target.role !== 'mall_admin' || target.reports_to !== req.user.id) {
      throw new AppError(403, 'That mall admin does not report to you.');
    }
    // Second guard: their branch must be one of the owner's (inactive ones included).
    const scope = await resolveScope(req.user, { includeInactive: true });
    const current = await assignments.mallAdminAssignments(target.id);
    if (!current.branches.some((b) => scope.branchIds.includes(b.id))) {
      throw new AppError(403, 'That mall admin does not report to you.');
    }
    return target;
  }
  throw new AppError(403, 'You do not have access to this action.');
}

accountsRouter.get('/', requireRole('supervisor'), async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'created' });
    const opts = {
      ...paging,
      search: paging.search,
      status: req.query.status,
      sortOrder: req.query.sortOrder ? paging.sortOrder : 'DESC',
    };
    if (req.user.role === 'superadmin') {
      opts.role = req.query.role || null;
      if (req.query.status === 'unassigned') {
        opts.status = null;
        opts.unassignedOnly = true;
      }
      if (req.query.status === 'no_owner') {
        opts.status = null;
        opts.noOwnerOnly = true;
      }
    } else {
      // A mall owner sees only the admins that report to them.
      opts.reportsTo = req.user.id;
      opts.roles = ['mall_admin'];
    }
    const { items, totalCount } = await users.list(opts);
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

// ---- Live checks for the create wizards (owner decisions 2026-10-22) ----
// Email: one account per email. A superadmin sees who holds it; mall owners and
// mall admins only learn that it is in use. Store-owner wizard: an active store
// owner's email adds the store to them (their name is shown); an inactive one is
// blocked until reactivated. An email waiting in someone's profile change
// request is allowed with a warning. Same full name: a warning only.
// Branch: the admins already placed there (several are allowed).
const checkSchema = z.object({
  email: z.string().trim().toLowerCase().max(255).optional(),
  fullName: z.string().trim().max(200).optional(),
  purpose: z.enum(['account', 'store_owner']).default('account'),
  branchId: z.coerce.number().int().positive().optional(),
});

async function checkEmail(email, purpose, req) {
  if (!z.string().email().safeParse(email).success) return { state: 'invalid' };
  const isSuper = req.user.role === 'superadmin';
  const other = await users.findByEmail(email);
  if (other) {
    const account = { id: other.id, fullName: other.full_name, role: other.role, isActive: !!other.is_active };
    if (purpose === 'store_owner' && other.role === 'store_owner') {
      let canOpen = isSuper;
      if (!isSuper) {
        const scope = await resolveScope(req.user);
        const list = await owners.storesForOwner(other.id);
        canOpen = list.length === 0 || list.some((s) => scope.branchIds.includes(s.branchId));
      }
      return { state: other.is_active ? 'store_owner' : 'inactive', account, canOpen };
    }
    const state = other.is_active ? 'taken' : 'inactive';
    return isSuper ? { state, account, canOpen: true } : { state };
  }
  if (await requests.emailPendingForOther(email, 0)) return { state: 'pending_request' };
  return { state: 'free' };
}

accountsRouter.get('/check', requireRole('supervisor', 'mall_admin'), async (req, res, next) => {
  try {
    const parsed = checkSchema.safeParse(req.query);
    if (!parsed.success) throw new AppError(400, parsed.error.issues[0]?.message ?? 'Invalid check.');
    const { email, fullName, purpose, branchId } = parsed.data;
    const isSuper = req.user.role === 'superadmin';
    const out = {};
    if (email) out.email = await checkEmail(email, purpose, req);
    if (fullName && fullName.length >= 2) {
      const found = await users.findByFullName(fullName);
      out.name = { count: found.total, ...(isSuper ? { matches: found.items } : {}) };
    }
    if (branchId && req.user.role !== 'mall_admin') {
      assertBranchInScope(await resolveScope(req.user), branchId);
      out.branchAdmins = (await assignments.branchAdmins(branchId)).map((x) => ({ id: x.id, fullName: x.fullName, isActive: x.isActive }));
    }
    res.json(out);
  } catch (err) {
    next(err);
  }
});

const idList = z.array(z.number().int().positive()).max(500).default([]);
const createSchema = z.object({
  email: z.string().trim().toLowerCase().email('Enter a valid email address.'),
  fullName: z.string().trim().min(2, 'Full name is required.').max(200),
  role: z.enum(['superadmin', 'supervisor', 'mall_admin'], { errorMap: () => ({ message: 'Role must be superadmin, supervisor or mall_admin.' }) }),
  // Initial assignment, applied right after the account is created so no account is left orphaned.
  assignments: z.object({ mallIds: idList, branchIds: idList }).optional(),
});

/**
 * Superadmin creates any role. A mall owner creates mall admins inside their own
 * branches. Who an admin reports to follows the ownership rule (utils/ownership.js).
 */
accountsRouter.post('/', requireRole('supervisor'), validate(createSchema), async (req, res, next) => {
  try {
    const { email, fullName, role } = req.body;
    const a = req.body.assignments ?? { mallIds: [], branchIds: [] };
    if (role === 'mall_admin' && a.branchIds.length > 1) throw new AppError(400, 'A mall admin manages exactly one branch.');
    if (req.user.role === 'supervisor') {
      if (role !== 'mall_admin') throw new AppError(403, 'You can only create mall admin accounts.');
      const scope = await resolveScope(req.user);
      if (!a.branchIds.length) throw new AppError(400, 'Choose the branch for the mall admin.');
      if (a.mallIds.length || a.branchIds.some((id) => !scope.branchIds.includes(id))) {
        throw new AppError(403, 'Some of those branches are outside your assigned scope.');
      }
    }
    const holder = await users.findByEmail(email);
    if (holder) throw new AppError(409, holder.is_active ? 'An account with that email already exists.' : 'That email belongs to an inactive account.');
    const tempPassword = generateTempPassword();
    const id = await users.create({
      email,
      fullName,
      role,
      passwordHash: await hashPassword(tempPassword),
      createdBy: req.user.id,
      mustChange: true,
    });
    if (a.mallIds.length || a.branchIds.length) {
      if (role === 'supervisor') await assignments.replaceSupervisorAssignments(id, { mallIds: a.mallIds, branchIds: a.branchIds }, req.user.id);
      else await assignments.replaceMallAdminAssignments(id, { branchIds: a.branchIds }, req.user.id);
    }
    await recordAudit(req, res, {
      action: role === 'superadmin' ? 'superadmin_created' : 'account_created',
      entityType: 'user',
      entityId: id,
      details: { email, role, assignments: req.body.assignments ?? null, createdByRole: req.user.role },
    });
    if (role !== 'superadmin') await applyReportsToRule(req, res, 'account created');
    // Round 19: a new mall admin starts with AI credits, as far as the wallet has free ones.
    let start = null;
    if (role === 'mall_admin') {
      start = await creditOps.grantStartCredits(id, req.user.id);
      if (start.amount > 0) await recordAudit(req, res, { action: 'ai_credits_started', entityType: 'user', entityId: id, details: { amount: start.amount } });
    }
    const user = users.toPublic(await users.findById(id));
    // The temporary password is returned once and never stored in clear.
    res.status(201).json({ user, tempPassword, ...(start ? { startCredits: start.amount, startNote: start.note } : {}) });
  } catch (err) {
    next(err);
  }
});

accountsRouter.get('/:id', requireRole('supervisor'), async (req, res, next) => {
  try {
    const target = await loadManageable(req, Number(req.params.id), { otherSuperadmin: true });
    const payload = { user: users.toPublic(target) };
    if (target.role === 'supervisor') payload.assignments = await assignments.supervisorAssignments(target.id);
    if (target.role === 'mall_admin') payload.assignments = await assignments.mallAdminAssignments(target.id);
    res.json(payload);
  } catch (err) {
    next(err);
  }
});

const updateSchema = z.object({
  fullName: z.string().trim().min(2, 'Full name is required.').max(200),
  email: z.string().trim().toLowerCase().email('Enter a valid email address.'),
});

accountsRouter.put('/:id', requireRole('supervisor'), validate(updateSchema), async (req, res, next) => {
  try {
    const target = await loadManageable(req, Number(req.params.id));
    const other = await users.findByEmail(req.body.email);
    if (other && other.id !== target.id) throw new AppError(409, 'Another account already uses that email.');
    if (req.body.email !== target.email && (await requests.emailPendingForOther(req.body.email, target.id))) {
      throw new AppError(409, "That email is waiting in someone else's change request.");
    }
    const updated = await users.updateProfile(target.id, req.body);
    await recordAudit(req, res, { action: 'account_updated', entityType: 'user', entityId: target.id, details: req.body });
    // Their own waiting request would undo this change when approved: it is cancelled.
    const cancelled = await requests.cancelForUser(target.id);
    if (cancelled) {
      await recordAudit(req, res, {
        action: 'profile_change_cancelled',
        entityType: 'profile_request',
        entityId: cancelled.id,
        details: { userId: target.id, reason: `Changed directly by ${req.user.email}` },
      });
    }
    res.json({ user: users.toPublic(updated) });
  } catch (err) {
    next(err);
  }
});

/**
 * Who a mall admin reports to is no longer set by hand (owner decision
 * 2026-10-22): it follows branch ownership (utils/ownership.js). The old route
 * answers 410 so an outdated screen gets a clear message.
 */
accountsRouter.put('/:id/reports-to', requireRole('supervisor'), (req, res, next) => {
  next(new AppError(410, 'Who a mall admin reports to is set automatically: the owner of their branch, else the mall\'s owner.'));
});

accountsRouter.post('/:id/deactivate', requireRole('supervisor'), async (req, res, next) => {
  try {
    const target = await loadManageable(req, Number(req.params.id), { otherSuperadmin: true });
    if (target.id === req.user.id) throw new AppError(400, 'You cannot deactivate your own account.');
    const updated = await users.deactivateKeepingASuperadmin(target.id);
    if (!updated) throw new AppError(409, 'At least one active superadmin must remain.');
    await recordAudit(req, res, { action: target.role === 'superadmin' ? 'superadmin_deactivated' : 'account_deactivated', entityType: 'user', entityId: target.id });
    // An inactive owner is skipped by the rule: their admins move to the next owner.
    if (target.role === 'supervisor') await applyReportsToRule(req, res, 'owner deactivated');
    // Round 19: unused AI credits go back to the wallet's free part; an open request closes.
    if (target.role === 'mall_admin') {
      const back = await creditOps.returnCredits(target.id, req.user.id);
      if (back.returned !== 0 || back.cancelledRequest) await recordAudit(req, res, { action: 'ai_credits_returned', entityType: 'user', entityId: target.id, details: back });
    }
    res.json({ user: users.toPublic(updated) });
  } catch (err) {
    next(err);
  }
});

accountsRouter.post('/:id/reactivate', requireRole('supervisor'), async (req, res, next) => {
  try {
    const target = await loadManageable(req, Number(req.params.id), { otherSuperadmin: true });
    const updated = await users.setActive(target.id, true);
    await recordAudit(req, res, { action: target.role === 'superadmin' ? 'superadmin_reactivated' : 'account_reactivated', entityType: 'user', entityId: target.id });
    if (target.role === 'supervisor') await applyReportsToRule(req, res, 'owner reactivated');
    // Round 19: a reactivated mall admin starts again with the starting credits, if free.
    let start = null;
    if (target.role === 'mall_admin' && !target.is_active) {
      start = await creditOps.grantStartCredits(target.id, req.user.id);
      if (start.amount > 0) await recordAudit(req, res, { action: 'ai_credits_started', entityType: 'user', entityId: target.id, details: { amount: start.amount, reactivated: true } });
    }
    res.json({ user: users.toPublic(updated), ...(start ? { startCredits: start.amount, startNote: start.note } : {}) });
  } catch (err) {
    next(err);
  }
});

accountsRouter.post('/:id/reset-password', requireRole('supervisor'), async (req, res, next) => {
  try {
    const target = await loadManageable(req, Number(req.params.id), { otherSuperadmin: true });
    const tempPassword = generateTempPassword();
    await users.setPassword(target.id, await hashPassword(tempPassword), { mustChange: true });
    await recordAudit(req, res, { action: target.role === 'superadmin' ? 'superadmin_password_reset' : 'password_reset_by_admin', entityType: 'user', entityId: target.id });
    res.json({ tempPassword });
  } catch (err) {
    next(err);
  }
});
