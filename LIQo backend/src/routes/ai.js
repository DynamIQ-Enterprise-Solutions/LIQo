import { Router } from 'express';
import { z } from 'zod';
import { requireRole } from '../middleware/requireRole.js';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as settings from '../repos/settings.js';
import * as gateway from '../ai/gateway.js';

// AI reading through IQGateway (Round 15). The browser only ever talks to these
// routes; the gateway key stays on the server.
export const aiRouter = Router();

/** Is AI reading ready, which model, and the wallet (for the credit bar). */
aiRouter.get('/status', requireRole('mall_admin'), async (req, res, next) => {
  try {
    const configured = gateway.aiConfigured();
    const model = await settings.getText('ai_model');
    let quota = null;
    let quotaError = null;
    if (configured) {
      try {
        quota = await gateway.quota();
      } catch (err) {
        quotaError = err instanceof AppError ? err.message : 'The credit balance could not be read.';
      }
    }
    res.json({ configured, model: model || null, quota, quotaError });
  } catch (err) {
    next(err);
  }
});

/** The models that can read plans, from the gateway's own list (a superadmin picks one). */
aiRouter.get('/models', requireRole('superadmin'), async (req, res, next) => {
  try {
    res.json({ items: gateway.readingModels(await gateway.models()), current: (await settings.getText('ai_model')) || null });
  } catch (err) {
    next(err);
  }
});

const modelSchema = z.object({
  model: z.string().trim().min(1, 'Choose a model.').max(100).regex(/^[A-Za-z0-9._:/@-]+$/, 'That is not a model name.'),
});

aiRouter.put('/model', requireRole('superadmin'), validate(modelSchema), async (req, res, next) => {
  try {
    const { model } = req.body;
    const offered = gateway.readingModels(await gateway.models());
    if (offered.length && !offered.some((m) => m.id === model)) {
      throw new AppError(400, 'That model cannot read plans through the AI gateway for this key (not a chat model, or not available).');
    }
    const before = (await settings.getText('ai_model')) || null;
    await settings.setMany({ ai_model: model }, req.user.id);
    await recordAudit(req, res, { action: 'ai_model_changed', entityType: 'settings', entityId: null, details: { from: before, to: model } });
    res.json({ model });
  } catch (err) {
    next(err);
  }
});
