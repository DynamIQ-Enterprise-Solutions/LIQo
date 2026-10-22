import { Router } from 'express';
import { query, sql } from '../db/pool.js';
import { resolveScope, inList } from '../utils/scope.js';
import { fromDateOnly, todayDateOnly } from '../utils/dates.js';
import { AppError } from '../middleware/errors.js';
import * as report from '../repos/analytics.js';

export const analyticsRouter = Router();

async function one(text, params = {}) {
  return (await query(text, params)).recordset[0].n;
}

/** Summary counts for the caller's scope, plus recent audit rows they may see. */
analyticsRouter.get('/overview', async (req, res, next) => {
  try {
    const scope = await resolveScope(req.user);
    const today = { type: sql.Date, value: fromDateOnly(todayDateOnly()) };

    let counts;
    let recentWhere = '';
    let recentParams = {};

    if (scope.all) {
      const [malls, branches, stores, accounts, logins7d, liveAnnouncements, pendingAnnouncements, mapPublications] = await Promise.all([
        one('SELECT COUNT(*) AS n FROM malls WHERE is_active = 1'),
        one('SELECT COUNT(*) AS n FROM branches b JOIN malls m ON m.id = b.mall_id WHERE b.is_active = 1 AND m.is_active = 1'),
        one('SELECT COUNT(*) AS n FROM stores s JOIN branches b ON b.id = s.branch_id JOIN malls m ON m.id = b.mall_id WHERE s.is_active = 1 AND b.is_active = 1 AND m.is_active = 1'),
        one('SELECT COUNT(*) AS n FROM users WHERE is_active = 1'),
        one("SELECT COUNT(*) AS n FROM audit_log WHERE action = 'login_success' AND created_at >= DATEADD(day, -7, SYSDATETIME())"),
        one("SELECT COUNT(*) AS n FROM announcements WHERE status = 'approved' AND starts_on <= @t AND ends_on >= @t", { t: today }),
        one("SELECT COUNT(*) AS n FROM announcements WHERE status = 'pending'"),
        one('SELECT COUNT(*) AS n FROM map_versions'),
      ]);
      counts = { malls, branches, stores, accounts, logins7d, liveAnnouncements, pendingAnnouncements, mapPublications };
    } else {
      const b = inList('id', scope.branchIds, 'b');
      const bs = inList('s.branch_id', scope.branchIds, 'c');
      const bm = inList('id', scope.mallIds, 'm');
      const ab = inList('ab.branch_id', scope.branchIds, 'd');

      // Accounts in scope (+ self): for a mall owner, the admins who report to them
      // (the ownership rule) and the owners of stores on their branches; for others,
      // the admins on their branches and those store owners (A10).
      const adminsSql =
        req.user.role === 'supervisor'
          ? `OR (u.role = 'mall_admin' AND u.reports_to = @me)`
          : `OR u.id IN (SELECT ma.user_id FROM mall_admin_assignments ma WHERE ${inList('ma.branch_id', scope.branchIds, 'e').clause})`;
      const accountsSql = `
        SELECT COUNT(DISTINCT u.id) AS n FROM users u
         WHERE (u.id = @me
            ${adminsSql}
            OR u.id IN (SELECT soa.user_id FROM store_owner_assignments soa JOIN stores s ON s.id = soa.store_id WHERE ${bs.clause}))`;
      // "Active accounts" counts active ones only (A3); sign-ins still count everyone in scope.
      const activeAccountsSql = accountsSql + ' AND u.is_active = 1';
      const accountParams = { me: { type: sql.Int, value: req.user.id }, ...inList('ma.branch_id', scope.branchIds, 'e').params, ...bs.params };

      const storeFilter = req.user.role === 'store_owner' ? inList('s.id', scope.storeIds, 'f') : bs;

      const bv = inList('mp.branch_id', scope.branchIds, 'g');
      const [malls, branches, stores, accounts, logins7d, liveAnnouncements, pendingAnnouncements, mapPublications] = await Promise.all([
        one(`SELECT COUNT(*) AS n FROM malls WHERE ${bm.clause}`, bm.params),
        one(`SELECT COUNT(*) AS n FROM branches WHERE ${b.clause}`, b.params),
        one(`SELECT COUNT(*) AS n FROM stores s WHERE ${storeFilter.clause} AND s.is_active = 1`, storeFilter.params),
        one(activeAccountsSql, accountParams),
        one(
          `SELECT COUNT(*) AS n FROM audit_log a WHERE a.action = 'login_success' AND a.created_at >= DATEADD(day, -7, SYSDATETIME())
             AND a.actor_id IN (${accountsSql.replace('SELECT COUNT(DISTINCT u.id) AS n', 'SELECT u.id')})`,
          accountParams,
        ),
        one(
          `SELECT COUNT(DISTINCT a.id) AS n FROM announcements a JOIN announcement_branches ab ON ab.announcement_id = a.id
            WHERE a.status = 'approved' AND a.starts_on <= @t AND a.ends_on >= @t AND ${ab.clause}`,
          { t: today, ...ab.params },
        ),
        one(
          `SELECT COUNT(DISTINCT a.id) AS n FROM announcements a JOIN announcement_branches ab ON ab.announcement_id = a.id
            WHERE a.status = 'pending' AND ${ab.clause}`,
          ab.params,
        ),
        one(`SELECT COUNT(*) AS n FROM map_versions v JOIN maps mp ON mp.id = v.map_id WHERE ${bv.clause}`, bv.params),
      ]);
      counts = { malls, branches, stores, accounts, logins7d, liveAnnouncements, pendingAnnouncements, mapPublications };

      // Mall owners see their own actions and their mall admins'; everyone else only their own.
      recentWhere = req.user.role === 'supervisor' ? 'WHERE actor_id = @me OR actor_id IN (SELECT id FROM users WHERE reports_to = @me)' : 'WHERE actor_id = @me';
      recentParams = { me: { type: sql.Int, value: req.user.id } };
    }

    const recent = (
      await query(
        `SELECT TOP 8 id, actor_email, action, entity_type, entity_id, created_at FROM audit_log ${recentWhere} ORDER BY created_at DESC`,
        recentParams,
      )
    ).recordset.map((r) => ({
      id: r.id,
      actorEmail: r.actor_email,
      action: r.action,
      entityType: r.entity_type,
      entityId: r.entity_id,
      createdAt: r.created_at,
    }));

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
