// Grouped queries behind GET /analytics/report. Every function takes the
// caller's resolved scope; superadmin (scope.all) sees everything, others only
// the branches resolveScope() gave them. Counts of records use the effective
// active rule (mall active AND branch active) like the lists do.
import { query, sql } from '../db/pool.js';
import { inList } from '../utils/scope.js';
import { fromDateOnly, toDateOnly, todayDateOnly } from '../utils/dates.js';

export const PERIODS = [7, 30, 90];

/** "b.id IN (...)" for scoped callers, "1=1" for superadmin. */
function branchFilter(scope, column, prefix) {
  if (scope.all) return { clause: '1=1', params: {} };
  return inList(column, scope.branchIds, prefix);
}

/**
 * Sub-select of user ids the caller may count: everyone for superadmin;
 * mall admins on scoped branches and owners of stores on them otherwise.
 * `includeSelf` adds the caller (for sign-in activity); the accounts table leaves the caller out.
 * `ownersOnly` limits the set to store owners (what a mall admin manages).
 */
function usersInScope(scope, me, { includeSelf, ownersOnly = false }) {
  if (scope.all) return { sql: 'SELECT id FROM users', params: {} };
  const so = inList('s.branch_id', scope.branchIds, 'ub');
  // Mall owners count the admins that report to them; mall admins count store owners only.
  const admins = ownersOnly ? '' : 'OR u.reports_to = @me';
  const self = includeSelf ? 'OR u.id = @me' : '';
  return {
    sql: `SELECT u.id FROM users u
           WHERE (u.id IN (SELECT soa.user_id FROM store_owner_assignments soa JOIN stores s ON s.id = soa.store_id WHERE ${so.clause})
              ${admins} ${self}) AND (u.id <> @me OR ${includeSelf ? 1 : 0} = 1)`,
    params: { ...so.params, me: { type: sql.Int, value: me } },
  };
}

/** Announcements that target at least one scoped branch. */
function announcementFilter(scope, prefix) {
  if (scope.all) return { clause: '1=1', params: {} };
  const ab = inList('ab.branch_id', scope.branchIds, prefix);
  return { clause: `a.id IN (SELECT ab.announcement_id FROM announcement_branches ab WHERE ${ab.clause})`, params: ab.params };
}

/** Editing stretches are audited as "map_edited" on the branch (one entry per 10 minutes of saving). */
function mapEditFilter(scope) {
  if (scope.all) return { clause: '1=1', params: {} };
  if (!scope.branchIds.length) return { clause: '1=0', params: {} };
  const params = {};
  const names = scope.branchIds.map((id, i) => {
    params[`me${i}`] = String(id);
    return `@me${i}`;
  });
  return { clause: `a.entity_id IN (${names.join(',')})`, params };
}

function dayList(days) {
  const out = [];
  const today = fromDateOnly(todayDateOnly());
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setDate(today.getDate() - i);
    out.push(toDateOnly(d));
  }
  return out;
}

const ACTIVITY_KEYS = ['logins', 'submitted', 'published', 'mapPublications', 'mapEdits', 'failedLogins', 'lockouts'];

/**
 * Per-day counts for the period and totals for the period before it.
 * Sign-ins and map saves come from the audit log, announcements and map
 * publications from their own tables (those carry the branch, the audit log does not).
 */
export async function activity(scope, me, days) {
  const since = { type: sql.DateTime2, value: new Date(Date.now() - 2 * days * 86400000) };
  const users = usersInScope(scope, me, { includeSelf: true });
  const ann = announcementFilter(scope, 'aa');
  const bv = branchFilter(scope, 'mp.branch_id', 'av');
  const edits = mapEditFilter(scope);

  const byDay = (text, params) => query(text, { since, ...params }).then((r) => r.recordset);
  const [logins, submitted, published, mapPubs, mapEdits, failed, locked] = await Promise.all([
    byDay(
      `SELECT CAST(a.created_at AS DATE) AS d, COUNT(*) AS n FROM audit_log a
        WHERE a.action = 'login_success' AND a.created_at >= @since AND a.actor_id IN (${users.sql})
        GROUP BY CAST(a.created_at AS DATE)`,
      users.params,
    ),
    byDay(
      `SELECT CAST(a.created_at AS DATE) AS d, COUNT(*) AS n FROM announcements a
        WHERE a.created_at >= @since AND ${ann.clause} GROUP BY CAST(a.created_at AS DATE)`,
      ann.params,
    ),
    // Published = posted directly by a supervisor / mall admin, or an owner submission that was approved.
    byDay(
      `SELECT d, SUM(n) AS n FROM (
         SELECT CAST(a.created_at AS DATE) AS d, COUNT(*) AS n FROM announcements a
          WHERE a.created_role <> 'store_owner' AND a.status = 'approved' AND a.created_at >= @since AND ${ann.clause}
          GROUP BY CAST(a.created_at AS DATE)
         UNION ALL
         SELECT CAST(a.reviewed_at AS DATE) AS d, COUNT(*) AS n FROM announcements a
          WHERE a.created_role = 'store_owner' AND a.status = 'approved' AND a.reviewed_at >= @since AND ${ann.clause}
          GROUP BY CAST(a.reviewed_at AS DATE)
       ) x GROUP BY d`,
      ann.params,
    ),
    byDay(
      `SELECT CAST(v.published_at AS DATE) AS d, COUNT(*) AS n FROM map_versions v JOIN maps mp ON mp.id = v.map_id
        WHERE v.published_at >= @since AND ${bv.clause} GROUP BY CAST(v.published_at AS DATE)`,
      bv.params,
    ),
    byDay(
      `SELECT CAST(a.created_at AS DATE) AS d, COUNT(*) AS n FROM audit_log a
        WHERE a.action = 'map_edited' AND a.created_at >= @since AND ${edits.clause} GROUP BY CAST(a.created_at AS DATE)`,
      edits.params,
    ),
    scope.all
      ? byDay(
          `SELECT CAST(a.created_at AS DATE) AS d, COUNT(*) AS n FROM audit_log a
            WHERE a.action IN ('login_failed', 'login_blocked_locked') AND a.created_at >= @since GROUP BY CAST(a.created_at AS DATE)`,
          {},
        )
      : [],
    scope.all
      ? byDay(
          `SELECT CAST(a.created_at AS DATE) AS d, COUNT(*) AS n FROM audit_log a
            WHERE a.action = 'account_locked' AND a.created_at >= @since GROUP BY CAST(a.created_at AS DATE)`,
          {},
        )
      : [],
  ]);

  const current = dayList(days);
  const currentSet = new Set(current);
  const rows = Object.fromEntries(current.map((d) => [d, Object.fromEntries(ACTIVITY_KEYS.map((k) => [k, 0]))]));
  const totals = Object.fromEntries(ACTIVITY_KEYS.map((k) => [k, 0]));
  const previous = Object.fromEntries(ACTIVITY_KEYS.map((k) => [k, 0]));
  const fold = (key, list) => {
    for (const r of list) {
      const d = toDateOnly(r.d);
      if (currentSet.has(d)) {
        rows[d][key] += r.n;
        totals[key] += r.n;
      } else {
        previous[key] += r.n;
      }
    }
  };
  fold('logins', logins);
  fold('submitted', submitted);
  fold('published', published);
  fold('mapPublications', mapPubs);
  fold('mapEdits', mapEdits);
  fold('failedLogins', failed);
  fold('lockouts', locked);
  return { days: current.map((d) => ({ date: d, ...rows[d] })), totals, previous };
}

export async function stores(scope) {
  const bf = branchFilter(scope, 'b.id', 'sb');
  const [byCategory, byBranch] = await Promise.all([
    query(
      `SELECT ISNULL(o.name, 'No category') AS name, COUNT(*) AS n
         FROM stores s JOIN branches b ON b.id = s.branch_id JOIN malls m ON m.id = b.mall_id
         LEFT JOIN branch_options o ON o.id = s.category_id
        WHERE s.is_active = 1 AND b.is_active = 1 AND m.is_active = 1 AND ${bf.clause}
        GROUP BY ISNULL(o.name, 'No category') ORDER BY n DESC, name`,
      bf.params,
    ).then((r) => r.recordset.map((x) => ({ name: x.name, count: x.n }))),
    query(
      `SELECT b.id, b.name AS branch, m.name AS mall,
              SUM(CASE WHEN s.is_active = 1 THEN 1 ELSE 0 END) AS active,
              SUM(CASE WHEN s.is_active = 0 THEN 1 ELSE 0 END) AS inactive,
              SUM(CASE WHEN s.is_active = 1 AND s.has_owner = 1 THEN 1 ELSE 0 END) AS with_owner,
              SUM(CASE WHEN s.is_active = 1 AND s.has_link = 1 THEN 1 ELSE 0 END) AS linked
         FROM branches b JOIN malls m ON m.id = b.mall_id
         LEFT JOIN (
           SELECT st.branch_id, st.is_active,
                  CASE WHEN EXISTS (SELECT 1 FROM store_owner_assignments soa WHERE soa.store_id = st.id) THEN 1 ELSE 0 END AS has_owner,
                  CASE WHEN EXISTS (SELECT 1 FROM store_spaces ss WHERE ss.store_id = st.id) THEN 1 ELSE 0 END AS has_link
             FROM stores st
         ) s ON s.branch_id = b.id
        WHERE b.is_active = 1 AND m.is_active = 1 AND ${bf.clause}
        GROUP BY b.id, b.name, m.name ORDER BY m.name, b.name`,
      bf.params,
    ).then((r) =>
      r.recordset.map((x) => ({
        branchId: x.id,
        branch: x.branch,
        mall: x.mall,
        active: x.active ?? 0,
        inactive: x.inactive ?? 0,
        withOwner: x.with_owner ?? 0,
        linked: x.linked ?? 0,
      })),
    ),
  ]);
  return { byCategory, byBranch };
}

export async function accounts(scope, me, role) {
  const users = usersInScope(scope, me, { includeSelf: false, ownersOnly: role === 'mall_admin' });
  const r = await query(
    `SELECT u.role, COUNT(*) AS total,
            SUM(CASE WHEN u.is_active = 1 THEN 1 ELSE 0 END) AS active,
            SUM(CASE WHEN u.is_active = 0 THEN 1 ELSE 0 END) AS inactive,
            SUM(u.unassigned) AS unassigned,
            SUM(CASE WHEN u.must_change_password = 1 THEN 1 ELSE 0 END) AS temp_password,
            SUM(CASE WHEN u.locked_until > SYSDATETIME() THEN 1 ELSE 0 END) AS locked
       FROM (
         SELECT x.role, x.is_active, x.must_change_password, x.locked_until,
                CASE WHEN x.role IN ('supervisor','mall_admin')
                      AND NOT EXISTS (SELECT 1 FROM supervisor_assignments sa WHERE sa.user_id = x.id)
                      AND NOT EXISTS (SELECT 1 FROM mall_admin_assignments ma WHERE ma.user_id = x.id) THEN 1 ELSE 0 END AS unassigned
           FROM users x WHERE x.id IN (${users.sql})
       ) u
      GROUP BY u.role`,
    users.params,
  );
  const order = ['superadmin', 'supervisor', 'mall_admin', 'store_owner'];
  const byRole = r.recordset
    .map((x) => ({
      role: x.role,
      total: x.total,
      active: x.active,
      inactive: x.inactive,
      unassigned: x.unassigned,
      tempPassword: x.temp_password,
      locked: x.locked,
    }))
    .sort((a, b) => order.indexOf(a.role) - order.indexOf(b.role));
  return { byRole };
}

export async function announcements(scope, days) {
  const ann = announcementFilter(scope, 'na');
  const today = { type: sql.Date, value: fromDateOnly(todayDateOnly()) };
  const since = { type: sql.DateTime2, value: new Date(Date.now() - days * 86400000) };
  const bf = branchFilter(scope, 'b.id', 'nb');

  const [status, source, pending, decision, byBranch] = await Promise.all([
    query(
      `SELECT a.status,
              SUM(CASE WHEN a.status = 'approved' AND a.starts_on <= @t AND a.ends_on >= @t THEN 1 ELSE 0 END) AS live,
              SUM(CASE WHEN a.status = 'approved' AND a.starts_on > @t THEN 1 ELSE 0 END) AS upcoming,
              SUM(CASE WHEN a.status = 'approved' AND a.ends_on < @t THEN 1 ELSE 0 END) AS expired,
              COUNT(*) AS n
         FROM announcements a WHERE ${ann.clause} GROUP BY a.status`,
      { t: today, ...ann.params },
    ).then((r) => r.recordset),
    query(`SELECT a.created_role AS role, COUNT(*) AS n FROM announcements a WHERE ${ann.clause} GROUP BY a.created_role`, ann.params).then((r) =>
      r.recordset.map((x) => ({ role: x.role, count: x.n })),
    ),
    query(
      `SELECT TOP 10 a.id, a.title, a.created_role, a.created_at, DATEDIFF(day, a.created_at, SYSDATETIME()) AS waiting_days,
              s.name AS store, u.full_name AS author,
              STUFF((SELECT ', ' + b.name FROM announcement_branches ab JOIN branches b ON b.id = ab.branch_id WHERE ab.announcement_id = a.id FOR XML PATH('')), 1, 2, '') AS branches
         FROM announcements a LEFT JOIN stores s ON s.id = a.store_id JOIN users u ON u.id = a.created_by
        WHERE a.status = 'pending' AND ${ann.clause} ORDER BY a.created_at ASC`,
      ann.params,
    ).then((r) =>
      r.recordset.map((x) => ({
        id: x.id,
        title: x.title,
        role: x.created_role,
        author: x.author,
        store: x.store,
        branches: x.branches,
        createdAt: x.created_at,
        waitingDays: x.waiting_days,
      })),
    ),
    query(
      `SELECT COUNT(*) AS n, AVG(CAST(DATEDIFF(minute, a.created_at, a.reviewed_at) AS FLOAT)) / 1440.0 AS avg_days
         FROM announcements a WHERE a.reviewed_at >= @since AND a.status IN ('approved','rejected') AND ${ann.clause}`,
      { since, ...ann.params },
    ).then((r) => r.recordset[0]),
    query(
      `SELECT b.id, b.name AS branch, m.name AS mall,
              SUM(CASE WHEN a.status = 'approved' AND a.starts_on <= @t AND a.ends_on >= @t THEN 1 ELSE 0 END) AS live,
              SUM(CASE WHEN a.status = 'pending' THEN 1 ELSE 0 END) AS pending,
              COUNT(a.id) AS total
         FROM branches b JOIN malls m ON m.id = b.mall_id
         LEFT JOIN announcement_branches ab ON ab.branch_id = b.id
         LEFT JOIN announcements a ON a.id = ab.announcement_id
        WHERE b.is_active = 1 AND m.is_active = 1 AND ${bf.clause}
        GROUP BY b.id, b.name, m.name ORDER BY m.name, b.name`,
      { t: today, ...bf.params },
    ).then((r) => r.recordset.map((x) => ({ branchId: x.id, branch: x.branch, mall: x.mall, live: x.live ?? 0, pending: x.pending ?? 0, total: x.total ?? 0 }))),
  ]);

  const byStatus = { pending: 0, approved: 0, rejected: 0 };
  const byTimeState = { live: 0, upcoming: 0, expired: 0 };
  for (const s of status) {
    byStatus[s.status] = s.n;
    byTimeState.live += s.live ?? 0;
    byTimeState.upcoming += s.upcoming ?? 0;
    byTimeState.expired += s.expired ?? 0;
  }
  return {
    byStatus,
    byTimeState,
    bySource: source,
    byBranch,
    pending,
    decided: decision.n ?? 0,
    avgDecisionDays: decision.avg_days == null ? null : Math.round(decision.avg_days * 10) / 10,
  };
}

/** Counts named spaces in a published layout without trusting its shape too much. */
function namedSpaces(layoutJson) {
  try {
    const layout = JSON.parse(layoutJson);
    let n = 0;
    for (const b of layout.buildings ?? []) {
      for (const l of b.levels ?? []) {
        for (const s of l.spaces ?? []) if (typeof s.name === 'string' && s.name.trim()) n += 1;
      }
    }
    return n;
  } catch {
    return 0;
  }
}

export async function maps(scope) {
  const bf = branchFilter(scope, 'b.id', 'mb');
  const r = await query(
    `SELECT b.id, b.name AS branch, m.name AS mall, mp.id AS map_id, mp.published_version_id, mp.updated_at,
            (SELECT COUNT(*) FROM map_versions v WHERE v.map_id = mp.id) AS versions,
            pv.version AS published_version, pv.published_at, pv.space_count, pv.layout_json, u.full_name AS published_by,
            (SELECT COUNT(DISTINCT ss.space_key) FROM store_spaces ss WHERE ss.branch_id = b.id) AS linked
       FROM branches b JOIN malls m ON m.id = b.mall_id
       LEFT JOIN maps mp ON mp.branch_id = b.id
       LEFT JOIN map_versions pv ON pv.id = mp.published_version_id
       LEFT JOIN users u ON u.id = pv.published_by
      WHERE b.is_active = 1 AND m.is_active = 1 AND ${bf.clause}
      ORDER BY m.name, b.name`,
    bf.params,
  );
  const summary = { none: 0, draft: 0, published: 0 };
  const byBranch = r.recordset.map((x) => {
    const state = x.map_id == null ? 'none' : x.published_version_id == null ? 'draft' : 'published';
    summary[state] += 1;
    return {
      branchId: x.id,
      branch: x.branch,
      mall: x.mall,
      state,
      versions: x.versions ?? 0,
      publishedVersion: x.published_version ?? null,
      publishedAt: x.published_at ?? null,
      publishedBy: x.published_by ?? null,
      lastEditedAt: x.updated_at ?? null,
      spaces: x.space_count ?? 0,
      named: x.layout_json ? namedSpaces(x.layout_json) : 0,
      linked: x.linked ?? 0,
    };
  });
  return { summary, byBranch };
}

/** Superadmin only: who is failing to sign in most in the period. */
export async function security(days) {
  const since = { type: sql.DateTime2, value: new Date(Date.now() - days * 86400000) };
  const r = await query(
    `SELECT TOP 5 ISNULL(a.actor_email, '(unknown)') AS email, COUNT(*) AS n
       FROM audit_log a WHERE a.action IN ('login_failed', 'login_blocked_locked') AND a.created_at >= @since
      GROUP BY a.actor_email ORDER BY n DESC`,
    { since },
  );
  return { topFailures: r.recordset.map((x) => ({ email: x.email, count: x.n })) };
}
