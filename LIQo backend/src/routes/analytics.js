import { Router } from 'express';
import { resolveScope } from '../utils/scope.js';
import { AppError } from '../middleware/errors.js';
import * as report from '../repos/analytics.js';

export const analyticsRouter = Router();

/** Summary counts for the caller's scope, plus recent audit rows they may see. */
analyticsRouter.get('/overview', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user);

    const { counts, recent } = await report.overview(scope, req.user);
    res.json({ counts, recent });
  } catch (err) {
    next(err);
  }
});

/**
 * Detailed breakdowns for the Analytics page: activity by day, stores,
 * accounts, announcements, map coverage, and (superadmin) sign-in security.
 * `days` is 7, 30 or 90 and drives the time-based parts only.
 */
analyticsRouter.get('/report', async (req, res, next) => {
  try {
    const days = Number(req.query.days ?? 7);
    if (!report.PERIODS.includes(days)) throw new AppError(400, 'days must be 7, 30 or 90.');
    const scope = await resolveScope(req.user);
    const [activity, stores, accounts, announcements, maps, security] = await Promise.all([
      report.activity(scope, req.user.id, days),
      report.stores(scope),
      report.accounts(scope, req.user.id, req.user.role),
      report.announcements(scope, days),
      report.maps(scope),
      scope.all ? report.security(days) : Promise.resolve(null),
    ]);
    res.json({
      days,
      from: activity.days[0]?.date ?? null,
      to: activity.days[activity.days.length - 1]?.date ?? null,
      activity,
      stores,
      accounts,
      announcements,
      maps,
      security,
      note: 'Shopper traffic, map views and searches are not available yet: no shopper app is connected.',
    });
  } catch (err) {
    next(err);
  }
});
