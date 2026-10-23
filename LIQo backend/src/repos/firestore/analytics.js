// The analytics behind GET /analytics/report and the overview, on Firestore
// (P1-06A). Audit-based numbers (sign-ins, map edits, failed sign-ins) come
// from the daily running totals the audit writes (_daily/<day>), never from
// scanning the audit log. The rest counts the small record collections in
// memory, with the same rules as mssql/analytics.js.
import { col, all, dayKey } from '../../db/firestore.js';
import { mapFiles } from '../../storage/files.js';
import { toDateOnly, todayDateOnly, fromDateOnly } from '../../utils/dates.js';
import { byId, compare } from './util.js';

export const PERIODS = [7, 30, 90];

const DAY = 86400000;
const inScope = (scope, branchId) => scope.all || scope.branchIds.map(Number).includes(Number(branchId));
const localDay = (d) => toDateOnly(d instanceof Date ? d : new Date(d));

async function load(...names) {
  return Promise.all(names.map((n) => all(col(n))));
}

/** The running-total docs from [sinceMs] on, as [{ day, data }]. */
async function dailyFrom(sinceMs) {
  const first = dayKey(new Date(sinceMs));
  const snap = await col('_daily').get();
  return snap.docs.filter((d) => d.id >= first).map((d) => ({ day: d.id, data: d.data() }));
}

/** Store owners of stores on scoped branches, plus (unless ownersOnly) those reporting to [me]; self only with includeSelf. */
function usersInScope(scope, me, { users, stores, ownerLinks }, { includeSelf, ownersOnly = false }) {
  if (scope.all) return new Set(users.map((u) => u.id));
  const storeBranch = new Map(stores.map((s) => [s.id, s.branch_id]));
  const ids = new Set(ownerLinks.filter((l) => inScope(scope, storeBranch.get(l.store_id))).map((l) => l.user_id));
  if (!ownersOnly) for (const u of users) if (u.reports_to === me) ids.add(u.id);
  if (includeSelf) ids.add(me);
  else ids.delete(me);
  return ids;
}

const announcementInScope = (scope, a) => scope.all || (a.branch_ids ?? []).some((b) => inScope(scope, b));

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

/** Per-day counts for the period and totals for the period before it. */
export async function activity(scope, me, days) {
  const sinceMs = Date.now() - 2 * days * DAY;
  const [[users, stores, ownerLinks, announcements, versions, maps], daily] = await Promise.all([
    load('users', 'stores', 'store_owner_assignments', 'announcements', 'map_versions', 'maps'),
    dailyFrom(sinceMs),
  ]);
  const people = usersInScope(scope, me, { users, stores, ownerLinks }, { includeSelf: true });
  const mapBranch = new Map(maps.map((m) => [m.id, m.branch_id]));

  const current = dayList(days);
  const currentSet = new Set(current);
  const rows = Object.fromEntries(current.map((d) => [d, Object.fromEntries(ACTIVITY_KEYS.map((k) => [k, 0]))]));
  const totals = Object.fromEntries(ACTIVITY_KEYS.map((k) => [k, 0]));
  const previous = Object.fromEntries(ACTIVITY_KEYS.map((k) => [k, 0]));
  const add = (key, day, n = 1) => {
    if (!n) return;
    if (currentSet.has(day)) {
      rows[day][key] += n;
      totals[key] += n;
    } else {
      previous[key] += n;
    }
  };
  const since = new Date(sinceMs);

  for (const { day, data } of daily) {
    if (scope.all) {
      add('logins', day, data.login_success ?? 0);
      add('mapEdits', day, data.map_edited ?? 0);
      add('failedLogins', day, (data.login_failed ?? 0) + (data.login_blocked_locked ?? 0));
      add('lockouts', day, data.account_locked ?? 0);
    } else {
      for (const [id, v] of Object.entries(data._actors ?? {})) if (people.has(Number(id))) add('logins', day, v.login_success ?? 0);
      for (const [id, v] of Object.entries(data._branches ?? {})) if (inScope(scope, id)) add('mapEdits', day, v.map_edited ?? 0);
    }
  }
  for (const a of announcements) {
    if (!announcementInScope(scope, a)) continue;
    if (a.created_at >= since) add('submitted', localDay(a.created_at));
    // Published = posted directly by a mall owner / mall admin, or an owner submission that was approved.
    if (a.status === 'approved') {
      if (a.created_role !== 'store_owner' && a.created_at >= since) add('published', localDay(a.created_at));
      if (a.created_role === 'store_owner' && a.reviewed_at && a.reviewed_at >= since) add('published', localDay(a.reviewed_at));
    }
  }
  for (const v of versions) if (v.published_at >= since && inScope(scope, mapBranch.get(v.map_id))) add('mapPublications', localDay(v.published_at));

  return { days: current.map((d) => ({ date: d, ...rows[d] })), totals, previous };
}

const activeChain = (branch, mall) => !!branch?.is_active && !!mall?.is_active;

export async function stores(scope) {
  const [stores, branches, malls, options, ownerLinks, spaces] = await load('stores', 'branches', 'malls', 'branch_options', 'store_owner_assignments', 'store_spaces');
  const b = byId(branches);
  const m = byId(malls);
  const o = byId(options);
  const owned = new Set(ownerLinks.map((l) => l.store_id));
  const linked = new Set(spaces.map((s) => s.store_id));

  const cats = new Map();
  for (const s of stores) {
    const br = b.get(s.branch_id);
    if (!s.is_active || !activeChain(br, m.get(br?.mall_id)) || !inScope(scope, s.branch_id)) continue;
    const name = o.get(s.category_id)?.name ?? 'No category';
    cats.set(name, (cats.get(name) ?? 0) + 1);
  }
  const byCategory = [...cats.entries()].map(([name, count]) => ({ name, count })).sort((x, y) => y.count - x.count || compare(x.name, y.name));

  const byBranch = branches
    .filter((br) => activeChain(br, m.get(br.mall_id)) && inScope(scope, br.id))
    .map((br) => {
      const mine = stores.filter((s) => s.branch_id === br.id);
      const active = mine.filter((s) => s.is_active);
      return {
        branchId: br.id,
        branch: br.name,
        mall: m.get(br.mall_id).name,
        active: active.length,
        inactive: mine.length - active.length,
        withOwner: active.filter((s) => owned.has(s.id)).length,
        linked: active.filter((s) => linked.has(s.id)).length,
      };
    })
    .sort((x, y) => compare(x.mall, y.mall) || compare(x.branch, y.branch));
  return { byCategory, byBranch };
}

export async function accounts(scope, me, role) {
  const [users, stores, ownerLinks, supLinks, adminLinks] = await load('users', 'stores', 'store_owner_assignments', 'supervisor_assignments', 'mall_admin_assignments');
  const ids = usersInScope(scope, me, { users, stores, ownerLinks }, { includeSelf: false, ownersOnly: role === 'mall_admin' });
  const placed = new Set([...supLinks.map((l) => l.user_id), ...adminLinks.map((l) => l.user_id)]);
  const now = new Date();
  const groups = new Map();
  for (const u of users) {
    if (!ids.has(u.id)) continue;
    const g = groups.get(u.role) ?? { role: u.role, total: 0, active: 0, inactive: 0, unassigned: 0, tempPassword: 0, locked: 0 };
    g.total += 1;
    if (u.is_active) g.active += 1;
    else g.inactive += 1;
    if ((u.role === 'supervisor' || u.role === 'mall_admin') && !placed.has(u.id)) g.unassigned += 1;
    if (u.must_change_password) g.tempPassword += 1;
    if (u.locked_until && u.locked_until > now) g.locked += 1;
    groups.set(u.role, g);
  }
  const order = ['superadmin', 'supervisor', 'mall_admin', 'store_owner'];
  return { byRole: [...groups.values()].sort((a, b) => order.indexOf(a.role) - order.indexOf(b.role)) };
}

/** Calendar days between two times (SQL DATEDIFF(day, ...)). */
const daysBetween = (from, to) => Math.round((fromDateOnly(localDay(to)) - fromDateOnly(localDay(from))) / DAY);

export async function announcements(scope, days) {
  const [anns, branches, malls, stores, users] = await load('announcements', 'branches', 'malls', 'stores', 'users');
  const today = todayDateOnly();
  const since = new Date(Date.now() - days * DAY);
  const b = byId(branches);
  const m = byId(malls);
  const s = byId(stores);
  const u = byId(users);
  const mine = anns.filter((a) => announcementInScope(scope, a));
  const live = (a) => a.status === 'approved' && a.starts_on <= today && a.ends_on >= today;

  const byStatus = { pending: 0, approved: 0, rejected: 0 };
  const byTimeState = { live: 0, upcoming: 0, expired: 0 };
  const roles = new Map();
  for (const a of mine) {
    byStatus[a.status] = (byStatus[a.status] ?? 0) + 1;
    if (a.status === 'approved') {
      if (live(a)) byTimeState.live += 1;
      else if (a.starts_on > today) byTimeState.upcoming += 1;
      else if (a.ends_on < today) byTimeState.expired += 1;
    }
    roles.set(a.created_role, (roles.get(a.created_role) ?? 0) + 1);
  }
  const bySource = [...roles.entries()].map(([role, count]) => ({ role, count }));

  const now = new Date();
  const pending = mine
    .filter((a) => a.status === 'pending')
    .sort((x, y) => x.created_at - y.created_at)
    .slice(0, 10)
    .map((a) => ({
      id: a.id,
      title: a.title,
      role: a.created_role,
      author: u.get(a.created_by)?.full_name ?? null,
      store: a.store_id != null ? s.get(a.store_id)?.name ?? null : null,
      branches: (a.branch_ids ?? []).map((id) => b.get(id)?.name).filter(Boolean).join(', ') || null,
      createdAt: a.created_at,
      waitingDays: daysBetween(a.created_at, now),
    }));

  const decidedRows = mine.filter((a) => a.reviewed_at && a.reviewed_at >= since && (a.status === 'approved' || a.status === 'rejected'));
  const avgMinutes = decidedRows.length
    ? decidedRows.reduce((acc, a) => acc + Math.floor((a.reviewed_at - a.created_at) / 60000), 0) / decidedRows.length
    : null;

  const byBranch = branches
    .filter((br) => activeChain(br, m.get(br.mall_id)) && inScope(scope, br.id))
    .map((br) => {
      const here = anns.filter((a) => (a.branch_ids ?? []).includes(br.id));
      return {
        branchId: br.id,
        branch: br.name,
        mall: m.get(br.mall_id).name,
        live: here.filter(live).length,
        pending: here.filter((a) => a.status === 'pending').length,
        total: here.length,
      };
    })
    .sort((x, y) => compare(x.mall, y.mall) || compare(x.branch, y.branch));

  return {
    byStatus,
    byTimeState,
    bySource,
    byBranch,
    pending,
    decided: decidedRows.length,
    avgDecisionDays: avgMinutes == null ? null : Math.round((avgMinutes / 1440) * 10) / 10,
  };
}

/** Counts named spaces in a published layout without trusting its shape too much. */
function namedSpaces(layout) {
  try {
    let n = 0;
    for (const b of layout?.buildings ?? []) {
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
  const [branches, malls, maps, versions, users, spaces] = await load('branches', 'malls', 'maps', 'map_versions', 'users', 'store_spaces');
  const m = byId(malls);
  const u = byId(users);
  const v = byId(versions);
  const mapByBranch = new Map(maps.map((x) => [x.branch_id, x]));
  const summary = { none: 0, draft: 0, published: 0 };
  const byBranch = branches
    .filter((br) => activeChain(br, m.get(br.mall_id)) && inScope(scope, br.id))
    .sort((x, y) => compare(m.get(x.mall_id).name, m.get(y.mall_id).name) || compare(x.name, y.name))
    .map((br) => {
      const mp = mapByBranch.get(br.id);
      const pv = mp?.published_version_id != null ? v.get(mp.published_version_id) : null;
      const state = !mp ? 'none' : !pv ? 'draft' : 'published';
      summary[state] += 1;
      return {
        branchId: br.id,
        branch: br.name,
        mall: m.get(br.mall_id).name,
        state,
        versions: mp ? versions.filter((x) => x.map_id === mp.id).length : 0,
        publishedVersion: pv?.version ?? null,
        publishedAt: pv?.published_at ?? null,
        publishedBy: pv ? u.get(pv.published_by)?.full_name ?? null : null,
        lastEditedAt: mp?.updated_at ?? null,
        spaces: pv?.space_count ?? 0,
        named: pv ? namedSpaces(mapFiles.readVersion(br.id, pv.version)) : 0,
        linked: new Set(spaces.filter((s) => s.branch_id === br.id).map((s) => s.space_key)).size,
      };
    });
  return { summary, byBranch };
}

/** Superadmin only: who is failing to sign in most in the period. */
export async function security(days) {
  const totals = new Map();
  for (const { data } of await dailyFrom(Date.now() - days * DAY)) {
    for (const [email, v] of Object.entries(data._emails ?? {})) {
      totals.set(email, (totals.get(email) ?? 0) + (v.login_failed ?? 0) + (v.login_blocked_locked ?? 0));
    }
  }
  const topFailures = [...totals.entries()]
    .map(([email, count]) => ({ email, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);
  return { topFailures };
}

/** The overview cards for the caller's scope, plus the recent audit rows they may see. */
export async function overview(scope, user) {
  const [[malls, branches, stores, users, anns, versions, maps, ownerLinks, adminLinks], daily] = await Promise.all([
    load('malls', 'branches', 'stores', 'users', 'announcements', 'map_versions', 'maps', 'store_owner_assignments', 'mall_admin_assignments'),
    dailyFrom(Date.now() - 7 * DAY),
  ]);
  const m = byId(malls);
  const b = byId(branches);
  const today = todayDateOnly();
  const live = (a) => a.status === 'approved' && a.starts_on <= today && a.ends_on >= today;
  const mapBranch = new Map(maps.map((x) => [x.id, x.branch_id]));
  let counts;
  let recentActors = null;

  if (scope.all) {
    counts = {
      malls: malls.filter((x) => x.is_active).length,
      branches: branches.filter((x) => activeChain(x, m.get(x.mall_id))).length,
      stores: stores.filter((s) => s.is_active && activeChain(b.get(s.branch_id), m.get(b.get(s.branch_id)?.mall_id))).length,
      accounts: users.filter((x) => x.is_active).length,
      logins7d: daily.reduce((acc, d) => acc + (d.data.login_success ?? 0), 0),
      liveAnnouncements: anns.filter(live).length,
      pendingAnnouncements: anns.filter((a) => a.status === 'pending').length,
      mapPublications: versions.length,
    };
  } else {
    // Accounts in scope (+ self): for a mall owner, the admins who report to them
    // and the owners of stores on their branches; for others, the admins on their
    // branches and those store owners (A10).
    const storeBranch = new Map(stores.map((s) => [s.id, s.branch_id]));
    const ids = new Set([user.id]);
    if (user.role === 'supervisor') {
      for (const x of users) if (x.role === 'mall_admin' && x.reports_to === user.id) ids.add(x.id);
    } else {
      for (const l of adminLinks) if (inScope(scope, l.branch_id)) ids.add(l.user_id);
    }
    for (const l of ownerLinks) if (inScope(scope, storeBranch.get(l.store_id))) ids.add(l.user_id);
    const storeOk = user.role === 'store_owner' ? (s) => scope.storeIds.map(Number).includes(s.id) : (s) => inScope(scope, s.branch_id);
    const scopedAnns = anns.filter((a) => (a.branch_ids ?? []).some((x) => inScope(scope, x)));
    counts = {
      malls: malls.filter((x) => scope.mallIds.map(Number).includes(x.id)).length,
      branches: branches.filter((x) => inScope(scope, x.id)).length,
      stores: stores.filter((s) => storeOk(s) && s.is_active).length,
      accounts: users.filter((x) => ids.has(x.id) && x.is_active).length,
      logins7d: daily.reduce((acc, d) => acc + Object.entries(d.data._actors ?? {}).reduce((n, [id, v]) => n + (ids.has(Number(id)) ? v.login_success ?? 0 : 0), 0), 0),
      liveAnnouncements: scopedAnns.filter(live).length,
      pendingAnnouncements: scopedAnns.filter((a) => a.status === 'pending').length,
      mapPublications: versions.filter((v) => inScope(scope, mapBranch.get(v.map_id))).length,
    };
    // Mall owners see their own actions and their mall admins'; everyone else only their own.
    recentActors = user.role === 'supervisor' ? [user.id, ...users.filter((x) => x.reports_to === user.id).map((x) => x.id)] : [user.id];
  }

  const recent = (await recentAudit(recentActors)).map((r) => ({
    id: r.id,
    actorEmail: r.actor_email,
    action: r.action,
    entityType: r.entity_type,
    entityId: r.entity_id,
    createdAt: r.created_at,
  }));
  return { counts, recent };
}

/** The 8 newest audit rows, of everyone (null) or of these actors. */
async function recentAudit(actorIds) {
  if (!actorIds) return all(col('audit_log').orderBy('created_at', 'desc').limit(8));
  const rows = [];
  for (let i = 0; i < actorIds.length; i += 30) {
    rows.push(...(await all(col('audit_log').where('actor_id', 'in', actorIds.slice(i, i + 30)).orderBy('created_at', 'desc').limit(8))));
  }
  return rows.sort((a, b) => b.created_at - a.created_at).slice(0, 8);
}
