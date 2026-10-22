import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as users from '../repos/users.js';
import * as assignments from '../repos/assignments.js';
import { resolveScope } from '../utils/scope.js';
import { applyReportsToRule } from '../utils/ownership.js';

export const assignmentsRouter = Router();

const idList = z.array(z.number().int().positive()).max(500);

async function loadUserWithRole(id, role) {
  const user = await users.findById(id);
  if (!user) throw new AppError(404, 'Account not found.');
  if (user.role !== role) throw new AppError(400, `That account is not a ${role.replace('_', ' ')}.`);
  return user;
}

// ---- Supervisors (superadmin only) ----

assignmentsRouter.get('/supervisors/:userId', requireRole('superadmin'), async (req, res, next) => {
  try {
    const user = await loadUserWithRole(Number(req.params.userId), 'supervisor');
    res.json({ user: users.toPublic(user), ...(await assignments.supervisorAssignments(user.id)) });
  } catch (err) {
    next(err);
  }
});

assignmentsRouter.put(
  '/supervisors/:userId',
  requireRole('superadmin'),
  validate(z.object({ mallIds: idList.default([]), branchIds: idList.default([]) })),
  async (req, res, next) => {
    try {
      const user = await loadUserWithRole(Number(req.params.userId), 'supervisor');
      const result = await assignments.replaceSupervisorAssignments(user.id, req.body, req.user.id);
      await recordAudit(req, res, { action: 'supervisor_assignments_updated', entityType: 'user', entityId: user.id, details: req.body });
      await applyReportsToRule(req, res, 'owner assignments changed');
      res.json({ user: users.toPublic(user), ...result });
    } catch (err) {
      if (err.number === 547) return next(new AppError(400, 'One of the malls or branches does not exist.'));
      next(err);
    }
  },
);

// ---- Mall admins (superadmin; supervisor within scope) ----

assignmentsRouter.get('/mall-admins/:userId', requireRole('supervisor'), async (req, res, next) => {
  try {
    const user = await loadUserWithRole(Number(req.params.userId), 'mall_admin');
    const current = await assignments.mallAdminAssignments(user.id);
    if (req.user.role === 'supervisor' && user.reports_to !== req.user.id) {
      throw new AppError(403, 'That mall admin does not report to you.');
    }
    res.json({ user: users.toPublic(user), ...current });
  } catch (err) {
    next(err);
  }
});

assignmentsRouter.put(
  '/mall-admins/:userId',
  requireRole('supervisor'),
  validate(z.object({ branchIds: idList.default([]) })),
  async (req, res, next) => {
    try {
      const user = await loadUserWithRole(Number(req.params.userId), 'mall_admin');
      let branchIds = req.body.branchIds;
      if (branchIds.length > 1) throw new AppError(400, 'A mall admin manages exactly one branch.');

      if (req.user.role === 'supervisor') {
        // An owner may only move their own admin between branches inside their own scope.
        // Branches outside the scope stay untouched.
        if (user.reports_to !== req.user.id) throw new AppError(403, 'That mall admin does not report to you.');
        // The new branch must be active and in scope; the admin's current branch may be
        // one the owner deactivated (they can still move the admin off it).
        const scope = await resolveScope(req.user);
        const wide = await resolveScope(req.user, { includeInactive: true });
        const outside = branchIds.filter((id) => !scope.branchIds.includes(id));
        if (outside.length) throw new AppError(403, 'Some of those branches are outside your assigned scope.');
        const current = await assignments.mallAdminAssignments(user.id);
        const keep = current.branches.map((b) => b.id).filter((id) => !wide.branchIds.includes(id));
        if (keep.length && branchIds.length) throw new AppError(403, 'This admin manages a branch outside your scope; only a superadmin can move them.');
        branchIds = [...new Set([...keep, ...branchIds])];
      }

      const result = await assignments.replaceMallAdminAssignments(user.id, { branchIds }, req.user.id);
      await recordAudit(req, res, { action: 'mall_admin_assignments_updated', entityType: 'user', entityId: user.id, details: { branchIds } });
      await applyReportsToRule(req, res, 'admin moved');
      res.json({ user: users.toPublic(await users.findById(user.id)), ...result });
    } catch (err) {
      if (err.number === 547) return next(new AppError(400, 'One of the branches does not exist.'));
      next(err);
    }
  },
);
