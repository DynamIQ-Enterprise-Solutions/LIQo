import { Router } from 'express';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as settings from '../repos/settings.js';

export const settingsRouter = Router();

settingsRouter.get('/', requireRole('superadmin'), async (req, res, next) => {
  try {
    const values = await settings.getAll();
    res.json({ settings: values, rules: settings.RULES });
  } catch (err) {
    next(err);
  }
});

settingsRouter.put('/', requireRole('superadmin'), async (req, res, next) => {
  try {
    const body = req.body ?? {};
    const updates = {};
    for (const [key, rule] of Object.entries(settings.RULES)) {
      if (!(key in body)) continue;
      const n = Number(body[key]);
      if (!Number.isInteger(n)) throw new AppError(400, `${rule.label} must be a whole number.`);
      if (n < rule.min || n > rule.max) throw new AppError(400, `${rule.label} must be between ${rule.min} and ${rule.max}.`);
      updates[key] = n;
    }
    const unknown = Object.keys(body).filter((k) => !(k in settings.RULES));
    if (unknown.length) throw new AppError(400, `Unknown setting: ${unknown[0]}.`);
    if (Object.keys(updates).length === 0) throw new AppError(400, 'Nothing to update.');

    const values = await settings.setMany(updates, req.user.id);
    await recordAudit(req, res, { action: 'settings_updated', entityType: 'settings', entityId: null, details: updates });
    res.json({ settings: values, rules: settings.RULES });
  } catch (err) {
    next(err);
  }
});
