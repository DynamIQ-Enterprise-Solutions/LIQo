// Reads behind the public shopper routes (Round 21, P1-07). Only published,
// active or approved data: active branches of active malls with a published
// map, active stores, approved announcements. Never people, emails or drafts.
import { query, sql } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';
import { parseHours } from '../../utils/hours.js';
import { toDateOnly, fromDateOnly } from '../../utils/dates.js';

const int = (v) => ({ type: sql.Int, value: v });

/** Active branches of active malls that have a published map. */
export async function publishedBranches() {
  const r = await query(
    `SELECT b.id, b.name, b.mall_id, m.name AS mall_name, b.address, b.latitude, b.longitude, b.hours_json, b.opening_hours, v.version
       FROM branches b JOIN malls m ON m.id = b.mall_id
       JOIN maps mp ON mp.branch_id = b.id JOIN map_versions v ON v.id = mp.published_version_id
      WHERE b.is_active = 1 AND m.is_active = 1
      ORDER BY m.name, b.name, b.id`,
  );
  return r.recordset.map((x) => ({
    id: x.id,
    name: x.name,
    mallId: x.mall_id,
    mallName: x.mall_name,
    address: x.address ?? null,
    latitude: x.latitude == null ? null : Number(x.latitude),
    longitude: x.longitude == null ? null : Number(x.longitude),
    hours: parseHours(x.hours_json),
    hoursNote: x.opening_hours ?? null,
    version: x.version,
  }));
}

/** Active stores of these branches with their spaces and App category. */
export async function storesOf(branchIds) {
  if (!branchIds.length) return [];
  const f = inList('s.branch_id', branchIds, 'b');
  const r = await query(
    `SELECT s.id, s.branch_id, s.name, s.status, s.hours_json, s.opening_hours, s.contact_phone, s.description, s.logo_url,
            o.app_category
       FROM stores s LEFT JOIN branch_options o ON o.id = s.category_id
      WHERE s.is_active = 1 AND ${f.clause}
      ORDER BY s.id`,
    f.params,
  );
  const sp = inList('ss.branch_id', branchIds, 'c');
  const links = await query(`SELECT ss.store_id, ss.space_key FROM store_spaces ss WHERE ${sp.clause} ORDER BY ss.store_id, ss.space_key`, sp.params);
  const spaces = new Map();
  for (const l of links.recordset) {
    if (!spaces.has(l.store_id)) spaces.set(l.store_id, []);
    spaces.get(l.store_id).push(l.space_key);
  }
  return r.recordset.map((x) => ({
    id: x.id,
    branchId: x.branch_id,
    name: x.name,
    status: x.status ?? 'open',
    hours: parseHours(x.hours_json),
    hoursNote: x.opening_hours ?? null,
    phone: x.contact_phone ?? null,
    description: x.description ?? null,
    logoUrl: x.logo_url ?? null,
    category: x.app_category ?? 'other',
    spaceIds: spaces.get(x.id) ?? [],
  }));
}

/**
 * Approved announcements live on [today] ('yyyy-mm-dd', Philippine date) that
 * target at least one of [branchIds], with the targeted branches among them.
 * Announcements by a store owner whose store is no longer active are left out.
 */
export async function livePosts(branchIds, today) {
  if (!branchIds.length) return [];
  const t = { type: sql.Date, value: fromDateOnly(today) };
  const f = inList('ab.branch_id', branchIds, 'p');
  const r = await query(
    `SELECT a.id, a.title, a.body, a.image_url, a.image_key, a.starts_on, a.ends_on, a.created_role, a.store_id,
            s.name AS store_name, s.is_active AS store_active, ab.branch_id
       FROM announcements a
       JOIN announcement_branches ab ON ab.announcement_id = a.id
       LEFT JOIN stores s ON s.id = a.store_id
      WHERE a.status = 'approved' AND a.starts_on <= @t AND a.ends_on >= @t AND ${f.clause}
      ORDER BY a.id, ab.branch_id`,
    { t, ...f.params },
  );
  const byId = new Map();
  for (const x of r.recordset) {
    if (x.store_id != null && !x.store_active) continue;
    if (!byId.has(x.id)) {
      byId.set(x.id, {
        id: x.id,
        title: x.title,
        body: x.body,
        imageUrl: x.image_url ?? null,
        imageKey: x.image_key ?? null,
        startsOn: toDateOnly(x.starts_on),
        endsOn: toDateOnly(x.ends_on),
        storeId: x.store_id ?? null,
        storeName: x.store_name ?? null,
        branchIds: [],
      });
    }
    byId.get(x.id).branchIds.push(x.branch_id);
  }
  return [...byId.values()];
}

/** The picture of an approved, live announcement, or null (pictures are public only while their post is). */
export async function livePicture(key, today) {
  const r = await query(
    `SELECT TOP 1 a.image_key, a.image_mime FROM announcements a
      WHERE a.image_key = @k AND a.status = 'approved' AND a.ends_on >= @t`,
    { k: key, t: { type: sql.Date, value: fromDateOnly(today) } },
  );
  const x = r.recordset[0];
  return x ? { key: x.image_key, mime: x.image_mime } : null;
}

/** Search words kept per day and branch at most (as on Firestore). */
const MAX_WORDS = 500;

/** Adds per-day count rows [{day, branchId, event, storeId, dim, n}] into the totals. */
export async function addCounts(rows) {
  for (const c of rows) {
    if (c.event === 'search') {
      const key = { d: { type: sql.Date, value: fromDateOnly(c.day) }, b: int(c.branchId), k: c.dim ?? '' };
      const known = await query(`SELECT COUNT(*) AS n FROM shopper_counts WHERE day = @d AND branch_id = @b AND event = 'search' AND dim = @k`, key);
      if (!known.recordset[0].n) {
        const words = await query(`SELECT COUNT(*) AS n FROM shopper_counts WHERE day = @d AND branch_id = @b AND event = 'search'`, key);
        if (words.recordset[0].n >= MAX_WORDS) continue;
      }
    }
    await query(
      `MERGE shopper_counts WITH (HOLDLOCK) AS t
       USING (SELECT @d AS day, @b AS branch_id, @e AS event, @s AS store_id, @k AS dim) AS x
          ON t.day = x.day AND t.branch_id = x.branch_id AND t.event = x.event
         AND ((t.store_id IS NULL AND x.store_id IS NULL) OR t.store_id = x.store_id) AND t.dim = x.dim
       WHEN MATCHED THEN UPDATE SET n = t.n + @n
       WHEN NOT MATCHED THEN INSERT (day, branch_id, event, store_id, dim, n) VALUES (@d, @b, @e, @s, @k, @n);`,
      {
        d: { type: sql.Date, value: fromDateOnly(c.day) },
        b: int(c.branchId),
        e: c.event,
        s: c.storeId == null ? { type: sql.Int, value: null } : int(c.storeId),
        k: c.dim ?? '',
        n: int(c.n),
      },
    );
  }
}

/** Count totals of a branch (tests and the later analytics, P2-01). */
export async function countsOf(branchId) {
  const r = await query(`SELECT day, event, store_id, dim, n FROM shopper_counts WHERE branch_id = @b ORDER BY day, event, store_id, dim`, { b: int(branchId) });
  return r.recordset.map((x) => ({ day: toDateOnly(x.day), event: x.event, storeId: x.store_id ?? null, dim: x.dim, n: x.n }));
}
