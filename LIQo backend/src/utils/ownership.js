// Who a mall admin reports to is not picked by hand; it follows the owners of
// their branch (owner decisions 2026-10-22):
// - the owner of the admin's own branch (a branch-level owner) first,
// - otherwise the mall's whole-mall owner,
// - if several qualify, the one linked first;
// - inactive owner accounts are skipped (their admins come back on reactivation);
// - no owner at all: "No owner" (superadmins manage them) until one is linked.
// Recomputed after every change that can move the answer.
import { recordAudit } from '../middleware/audit.js';
import * as assignments from '../repos/assignments.js';

/**
 * Applies the rule to every mall admin and records one audit entry listing
 * the admins whose superior changed. Returns those changes.
 */
export async function applyReportsToRule(req, res, reason) {
  const changes = await assignments.recomputeReportsTo();
  if (changes.length) {
    await recordAudit(req, res, { action: 'reports_to_recomputed', entityType: 'user', entityId: null, details: { reason, changes } });
  }
  return changes;
}
