import { Router } from 'express';
import { query, sql } from '../db/pool.js';
import { AppError } from '../middleware/errors.js';
import { resolveScope, inList } from '../utils/scope.js';
import { pageEnvelope } from '../utils/pagination.js';

export const lookupsRouter = Router();

/**
 * One picker endpoint for every dropdown: GET /lookups/:name?search=&page=&pageSize=&parentId=
 * The name maps to a fixed query below; a client can never name a table directly.
 * Results are scoped to what the caller may see.
 */
const LOOKUPS = {
  malls: {
    from: 'malls m',
    id: 'm.id',
    label: 'm.name',
    active: 'm.is_active',
    scope: (scope) => (scope.all ? null : inList('m.id', scope.mallIds, 's')),
  },
  branches: {
    from: 'branches b JOIN malls m ON m.id = b.mall_id',
    id: 'b.id',
    label: "m.name + ' · ' + b.name",
    active: 'b.is_active',
    where: 'm.is_active = 1',
    parent: 'b.mall_id',
    scope: (scope) => (scope.all ? null : inList('b.id', scope.branchIds, 's')),
  },
  supervisors: {
    from: 'users u',
    id: 'u.id',
    label: "u.full_name + ' (' + u.email + ')'",
    active: 'u.is_active',
    where: "u.role = 'supervisor'",
    scope: (scope) => (scope.all ? null : { clause: '1=0', params: {} }),
  },
  // Mall admins with no branch yet: the only ones a mall may take on (one branch per admin).
  free_mall_admins: {
    from: 'users u',
    id: 'u.id',
    label: "u.full_name + ' (' + u.email + ')'",
    active: 'u.is_active',
    where: "u.role = 'mall_admin' AND NOT EXISTS (SELECT 1 FROM mall_admin_assignments ma WHERE ma.user_id = u.id)",
    scope: (scope) => (scope.all ? null : { clause: '1=0', params: {} }),
  },
  stores: {
    from: 'stores s JOIN branches b ON b.id = s.branch_id JOIN malls m ON m.id = b.mall_id',
    id: 's.id',
    label: "b.name + ' · ' + s.name",
    active: 's.is_active',
    where: 'b.is_active = 1 AND m.is_active = 1',
    parent: 's.branch_id',
    scope: (scope) => (scope.all ? null : inList('s.branch_id', scope.branchIds, 's')),
  },
  store_categories: {
    from: 'branch_options o',
    id: 'o.id',
    label: 'o.name',
    active: 'o.is_active',
    parent: 'o.branch_id',
    where: "o.kind = 'store_category'",
    scope: (scope) => (scope.all ? null : inList('o.branch_id', scope.branchIds, 's')),
  },
  mall_admins: {
    from: 'users u',
    id: 'u.id',
    label: "u.full_name + ' (' + u.email + ')'",
    active: 'u.is_active',
    where: "u.role = 'mall_admin'",
    scope: (scope) =>
      scope.all
        ? null
        : {
            clause: `u.id IN (SELECT ma.user_id FROM mall_admin_assignments ma WHERE ${inList('ma.branch_id', scope.branchIds, 's').clause})`,
            params: inList('ma.branch_id', scope.branchIds, 's').params,
          },
  },
};

lookupsRouter.get('/:name', async (req, res, next) => {
  try {
    const def = LOOKUPS[req.params.name];
    if (!def) throw new AppError(404, 'Unknown lookup.');

    const page = Math.max(1, Number(req.query.page) || 1);
    const pageSize = Math.min(50, Math.max(1, Number(req.query.pageSize) || 20));
    const search = (req.query.search || '').trim();
    const includeInactive = req.query.includeInactive === 'true';

    const where = [];
    const params = { offset: { type: sql.Int, value: (page - 1) * pageSize }, limit: { type: sql.Int, value: pageSize } };
    if (def.where) where.push(def.where);
    if (!includeInactive) where.push(`${def.active} = 1`);
    if (search) {
      where.push(`${def.label} LIKE @search`);
      params.search = `%${search}%`;
    }
    if (def.parent && req.query.parentId) {
      where.push(`${def.parent} = @parentId`);
      params.parentId = { type: sql.Int, value: Number(req.query.parentId) };
    }
    const scoped = def.scope(await resolveScope(req.user));
    if (scoped) {
      where.push(scoped.clause);
      Object.assign(params, scoped.params);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const total = (await query(`SELECT COUNT(*) AS n FROM ${def.from} ${whereSql}`, params)).recordset[0].n;
    const rows = (
      await query(
        `SELECT ${def.id} AS id, ${def.label} AS label, ${def.active} AS is_active
           FROM ${def.from} ${whereSql}
          ORDER BY ${def.label}
         OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
        params,
      )
    ).recordset;

    res.json(pageEnvelope(rows.map((r) => ({ id: r.id, label: r.label, isActive: !!r.is_active })), total, page, pageSize));
  } catch (err) {
    next(err);
  }
});
