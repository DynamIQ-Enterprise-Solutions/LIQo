import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { config } from './config.js';
import { requireAuth, blockUntilPasswordChanged } from './middleware/auth.js';
import { auditWrites } from './middleware/audit.js';
import { errorHandler, notFound } from './middleware/errors.js';
import { authRouter } from './routes/auth.js';
import { analyticsRouter } from './routes/analytics.js';
import { accountsRouter } from './routes/accounts.js';
import { mallsRouter } from './routes/malls.js';
import { branchesRouter } from './routes/branches.js';
import { assignmentsRouter } from './routes/assignments.js';
import { settingsRouter } from './routes/settings.js';
import { auditRouter } from './routes/audit.js';
import { lookupsRouter } from './routes/lookups.js';
import { announcementsRouter } from './routes/announcements.js';
import { storesRouter } from './routes/stores.js';
import { optionsRouter } from './routes/options.js';
import { ownersRouter } from './routes/owners.js';
import { profileRouter, profileRequestsRouter } from './routes/profile.js';
import { mapsRouter } from './routes/maps.js';
import { aiRouter } from './routes/ai.js';
import { creditsRouter } from './routes/credits.js';
import { reportsRouter, requestsRouter } from './routes/reports.js';

export function createApp() {
  const app = express();

  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet());

  // Dev: allow any http://localhost:* (Flutter picks a random port). Prod: explicit allow-list.
  app.use(
    cors({
      origin(origin, cb) {
        if (!origin) return cb(null, true);
        if (config.corsOrigins.length > 0) return cb(null, config.corsOrigins.includes(origin));
        return cb(null, /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin));
      },
    }),
  );

  app.use(express.json({ limit: '5mb' }));

  app.use('/api', (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });

  if (config.rateLimitOn) {
    app.use('/api', rateLimit({ windowMs: 60_000, limit: 1200, standardHeaders: true, legacyHeaders: false }));
    app.use(
      '/api/auth/login',
      rateLimit({
        windowMs: 15 * 60_000,
        limit: 15,
        skipSuccessfulRequests: true,
        message: { error: 'Too many failed sign-in attempts. Try again in 15 minutes.' },
      }),
    );
  }

  app.get('/api/health', (req, res) => res.json({ ok: true }));

  // Public + self-auditing auth routes.
  app.use('/api/auth', authRouter);

  // Everything below needs a signed-in user who has already changed a temp password.
  const api = express.Router();
  api.use(requireAuth, blockUntilPasswordChanged, auditWrites);
  api.use('/analytics', analyticsRouter);
  api.use('/accounts', accountsRouter);
  api.use('/malls', mallsRouter);
  api.use('/branches', branchesRouter);
  api.use('/assignments', assignmentsRouter);
  api.use('/settings', settingsRouter);
  api.use('/ai/credits', creditsRouter);
  api.use('/ai', aiRouter);
  api.use('/audit', auditRouter);
  api.use('/lookups', lookupsRouter);
  api.use('/announcements', announcementsRouter);
  api.use('/stores', storesRouter);
  api.use('/options', optionsRouter);
  api.use('/owners', ownersRouter);
  api.use('/maps', mapsRouter);
  api.use('/profile', profileRouter);
  api.use('/profile-requests', profileRequestsRouter);
  api.use('/reports', reportsRouter);
  api.use('/requests', requestsRouter);
  app.use('/api', api);

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
