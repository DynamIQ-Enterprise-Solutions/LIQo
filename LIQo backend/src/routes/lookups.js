import { Router } from 'express';
import { AppError } from '../middleware/errors.js';
import { resolveScope } from '../utils/scope.js';
import { pageEnvelope } from '../utils/pagination.js';
import { lookup } from '../repos/lookups.js';

export const lookupsRouter = Router();

/**
 * One picker endpoint for every dropdown: GET /lookups/:name?search=&page=&pageSize=&parentId=
 * The name maps to a fixed query in repos/lookups.js; a client can never name a table directly.
 * Results are scoped to what the caller may see.
 */
lookupsRouter.get('/:name', async (req, res, next) => {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const pageSize = Math.min(50, Math.max(1, Number(req.query.pageSize) || 20));
    const r = await lookup(req.params.name, {
      scope: await resolveScope(req.user),
      search: (req.query.search || '').trim(),
      parentId: req.query.parentId || null,
      includeInactive: req.query.includeInactive === 'true',
      page,
      pageSize,
    });
    if (!r) throw new AppError(404, 'Unknown lookup.');
    res.json(pageEnvelope(r.items, r.totalCount, page, pageSize));
  } catch (err) {
    next(err);
  }
});
