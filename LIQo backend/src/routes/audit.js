import { Router } from 'express';
import { requireRole } from '../middleware/requireRole.js';
import * as audit from '../repos/audit.js';
import { parsePaging, pageEnvelope } from '../utils/pagination.js';

export const auditRouter = Router();

const SORT = { created: 'a.created_at', action: 'a.action', actor: 'a.actor_email' };

function parseDate(value) {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

auditRouter.get('/', requireRole('superadmin'), async (req, res, next) => {
  try {
    const paging = parsePaging(req.query, { sortMap: SORT, defaultSort: 'created' });
    const from = parseDate(req.query.from);
    let to = parseDate(req.query.to);
    // "to" is a date; include the whole day.
    if (to && /^\d{4}-\d{2}-\d{2}$/.test(String(req.query.to))) to = new Date(to.getTime() + 24 * 60 * 60 * 1000);

    const { items, totalCount } = await audit.list({
      ...paging,
      sortOrder: req.query.sortOrder ? paging.sortOrder : 'DESC',
      actor: req.query.actor,
      action: req.query.action,
      from,
      to,
    });
    res.json(pageEnvelope(items, totalCount, paging.page, paging.pageSize));
  } catch (err) {
    next(err);
  }
});

auditRouter.get('/actions', requireRole('superadmin'), async (req, res, next) => {
  try {
    res.json({ actions: await audit.actions() });
  } catch (err) {
    next(err);
  }
});
