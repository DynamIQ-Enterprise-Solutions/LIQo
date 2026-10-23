// Reads behind the public shopper routes on Firestore (Round 21, P1-07): the
// same rules as mssql/shopper.js. Counts are one document per day and branch
// (shopper_counts/<day>_<branch>), so a batch costs one write per branch.
import { col, docOf, runTx, all, FieldValue } from '../../db/firestore.js';
import { parseHours } from '../../utils/hours.js';
import { byId, compare } from './util.js';

/** Search words kept per day and branch at most (bounds the document size). */
const MAX_WORDS = 500;

export async function publishedBranches() {
  const [branches, malls, maps] = await Promise.all([all(col('branches')), all(col('malls')), all(col('maps'))]);
  const m = byId(malls);
  const published = new Map(maps.filter((x) => x.published_version != null).map((x) => [x.branch_id, x.published_version]));
  return branches
    .filter((b) => b.is_active && m.get(b.mall_id)?.is_active && published.has(b.id))
    .map((b) => ({
      id: b.id,
      name: b.name,
      mallId: b.mall_id,
      mallName: m.get(b.mall_id).name,
      address: b.address ?? null,
      latitude: b.latitude == null ? null : Number(b.latitude),
      longitude: b.longitude == null ? null : Number(b.longitude),
      hours: parseHours(b.hours_json),
      hoursNote: b.opening_hours ?? null,
      version: published.get(b.id),
    }))
    .sort((a, b) => compare(a.mallName, b.mallName) || compare(a.name, b.name) || a.id - b.id);
}

export async function storesOf(branchIds) {
  if (!branchIds.length) return [];
  const wanted = new Set(branchIds.map(Number));
  const [stores, options, links] = await Promise.all([all(col('stores')), all(col('branch_options')), all(col('store_spaces'))]);
  const o = byId(options);
  const spaces = new Map();
  for (const l of links.filter((x) => wanted.has(x.branch_id)).sort((a, b) => a.store_id - b.store_id || compare(a.space_key, b.space_key))) {
    if (!spaces.has(l.store_id)) spaces.set(l.store_id, []);
    spaces.get(l.store_id).push(l.space_key);
  }
  return stores
    .filter((s) => s.is_active && wanted.has(s.branch_id))
    .sort((a, b) => a.id - b.id)
    .map((s) => ({
      id: s.id,
      branchId: s.branch_id,
      name: s.name,
      status: s.status ?? 'open',
      hours: parseHours(s.hours_json),
      hoursNote: s.opening_hours ?? null,
      phone: s.contact_phone ?? null,
      description: s.description ?? null,
      logoUrl: s.logo_url ?? null,
      category: (s.category_id != null ? o.get(s.category_id)?.app_category : null) ?? 'other',
      spaceIds: spaces.get(s.id) ?? [],
    }));
}

export async function livePosts(branchIds, today) {
  if (!branchIds.length) return [];
  const wanted = new Set(branchIds.map(Number));
  const [rows, stores] = await Promise.all([all(col('announcements').where('status', '==', 'approved')), all(col('stores'))]);
  const s = byId(stores);
  return rows
    .filter((a) => a.starts_on <= today && a.ends_on >= today)
    .filter((a) => a.store_id == null || s.get(a.store_id)?.is_active)
    .map((a) => ({ a, targets: (a.branch_ids ?? []).filter((b) => wanted.has(b)).sort((x, y) => x - y) }))
    .filter(({ targets }) => targets.length)
    .sort((x, y) => x.a.id - y.a.id)
    .map(({ a, targets }) => ({
      id: a.id,
      title: a.title,
      body: a.body,
      imageUrl: a.image_url ?? null,
      imageKey: a.image_key ?? null,
      startsOn: a.starts_on,
      endsOn: a.ends_on,
      storeId: a.store_id ?? null,
      storeName: a.store_id != null ? s.get(a.store_id)?.name ?? null : null,
      branchIds: targets,
    }));
}

export async function livePicture(key, today) {
  const rows = await all(col('announcements').where('image_key', '==', key));
  const a = rows.find((x) => x.status === 'approved' && x.ends_on >= today);
  return a ? { key: a.image_key, mime: a.image_mime } : null;
}

const countKey = (c) => `${c.event}|${c.storeId ?? ''}|${String(c.dim ?? '').split('|').join(' ')}`;

export async function addCounts(rows) {
  const groups = new Map();
  for (const c of rows) {
    const id = `${c.day}_${c.branchId}`;
    if (!groups.has(id)) groups.set(id, { day: c.day, branchId: c.branchId, items: [] });
    groups.get(id).items.push(c);
  }
  for (const [id, g] of groups) {
    await runTx(async (tx) => {
      const ref = docOf('shopper_counts', id);
      const cur = (await tx.get(ref)).data()?.counts ?? {};
      let words = Object.keys(cur).filter((k) => k.startsWith('search|')).length;
      const inc = {};
      for (const c of g.items) {
        const k = countKey(c);
        if (c.event === 'search' && !(k in cur) && !(k in inc)) {
          if (words >= MAX_WORDS) continue;
          words += 1;
        }
        inc[k] = (inc[k] ?? 0) + c.n;
      }
      const counts = Object.fromEntries(Object.entries(inc).map(([k, n]) => [k, FieldValue.increment(n)]));
      tx.set(ref, { day: g.day, branch_id: Number(g.branchId), counts }, { merge: true });
    });
  }
}

export async function countsOf(branchId) {
  const rows = await all(col('shopper_counts').where('branch_id', '==', Number(branchId)));
  const out = [];
  for (const r of rows) {
    for (const [k, n] of Object.entries(r.counts ?? {})) {
      const [event, store, ...dim] = k.split('|');
      out.push({ day: r.day, event, storeId: store === '' ? null : Number(store), dim: dim.join('|'), n });
    }
  }
  return out.sort((a, b) => compare(a.day, b.day) || compare(a.event, b.event) || (a.storeId ?? -1) - (b.storeId ?? -1) || compare(a.dim, b.dim));
}
