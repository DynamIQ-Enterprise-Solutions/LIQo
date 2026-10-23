// The public shopper service (Round 21, P1-07; contract in
// docs/shopper-package-format.md §7–§11, decisions in
// docs/shopper-hybrid-decisions.md §3). Read-only except anonymous counts;
// mounted before sign-in; never audited; only published, active or approved
// data, never people, emails or drafts. A written exception to the
// utils/scope.js rule (Blueprint §4.19): shoppers have no scope, the
// published-and-active filter is the scope.
import { Router } from 'express';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { z } from 'zod';
import { AppError } from '../middleware/errors.js';
import * as shopper from '../repos/shopper.js';
import * as maps from '../repos/maps.js';
import * as options from '../repos/options.js';
import * as outages from '../repos/outages.js';
import * as settings from '../repos/settings.js';
import { pictures } from '../storage/files.js';
import { spaceFloors } from '../maps/shopper/levels.js';
import { phToday, phIso, addDays } from '../utils/dates.js';

export const shopperRouter = Router();

export const FORMAT_VERSION = 1;
const POSTS_PER_PAGE = 10;
const COUNT_TYPES = ['place_opened', 'directions_started', 'directions_finished', 'category_tap', 'search', 'mall_opened'];
const MAX_EVENTS = 500;
const MAX_COUNT_BYTES = 256 * 1024;

/** The absolute base of this server, for picture links (behind the tunnel: its https address). */
const baseOf = (req) => `${req.protocol}://${req.get('host')}`;

/**
 * Sends JSON with an ETag (a hash of [tagOf], default the body) and answers 304
 * to a matching If-None-Match; gzips larger bodies when the phone accepts it.
 */
function send(req, res, body, { tagOf = body, maxAge = 60 } = {}) {
  const etag = `"${crypto.createHash('sha256').update(JSON.stringify(tagOf)).digest('hex').slice(0, 32)}"`;
  res.set('ETag', etag);
  res.set('Cache-Control', `public, max-age=${maxAge}`);
  res.set('Vary', 'Accept-Encoding');
  if (req.get('If-None-Match') === etag) return res.status(304).end();
  const json = Buffer.from(JSON.stringify(body));
  res.type('application/json');
  if (json.length > 1024 && /\bgzip\b/.test(req.get('Accept-Encoding') ?? '')) {
    res.set('Content-Encoding', 'gzip');
    return res.send(zlib.gzipSync(json));
  }
  return res.send(json);
}

// ---- Floors of a branch's stores, from its published map (cached per version, which never changes) ----

const floorCache = new Map();
async function floorsOf(branchId, version) {
  const key = `${branchId}:${version}`;
  if (floorCache.has(key)) return floorCache.get(key);
  const [pub, labels] = await Promise.all([maps.publishedLayout(branchId), options.list({ branchId, kind: 'floor_label', includeInactive: false })]);
  const floors = pub ? spaceFloors(pub.layout, labels.map((o) => o.name)) : new Map();
  if (floorCache.size > 500) floorCache.clear();
  floorCache.set(key, floors);
  return floors;
}

/** The package details the directory lists (step B, P1-08: built at publish). */
async function packageMeta() {
  return null;
}

shopperRouter.get('/directory', async (req, res, next) => {
  try {
    const branches = await shopper.publishedBranches();
    const stores = await shopper.storesOf(branches.map((b) => b.id));
    const items = [];
    for (const b of branches) {
      const floors = await floorsOf(b.id, b.version);
      const list = stores
        .filter((s) => s.branchId === b.id)
        .map((s) => ({ s, floor: s.spaceIds.map((id) => floors.get(id)).find(Boolean) }))
        .filter(({ floor }) => floor)
        .map(({ s, floor }) => ({ storeId: s.id, name: s.name, category: s.category, floor }));
      items.push({
        id: b.id,
        name: b.name,
        mallId: b.mallId,
        mallName: b.mallName,
        address: b.address ?? '',
        lat: b.latitude,
        lng: b.longitude,
        active: true,
        hours: b.hours,
        package: await packageMeta(b),
        stores: list,
      });
    }
    send(req, res, { branches: items, generatedAt: phIso(new Date()) }, { tagOf: items, maxAge: 60 });
  } catch (err) {
    next(err);
  }
});

/** An active branch of an active mall with a published map, or a 404 the app understands. */
async function publishedBranch(id) {
  const branchId = Number(id);
  const b = Number.isInteger(branchId) ? (await shopper.publishedBranches()).find((x) => x.id === branchId) : null;
  if (!b) throw new AppError(404, 'This mall is not on LIQo right now.');
  return b;
}

shopperRouter.get('/branches/:id/live', async (req, res, next) => {
  try {
    const b = await publishedBranch(req.params.id);
    const stores = (await shopper.storesOf([b.id]))
      .filter((s) => s.spaceIds.length)
      .map((s) => {
        const out = { storeId: s.id, spaceIds: s.spaceIds, name: s.name, category: s.category, status: s.status, hours: s.hours };
        if (s.hoursNote) out.hoursNote = s.hoursNote;
        if (s.phone) out.phone = s.phone;
        if (s.description) out.description = s.description;
        if (s.logoUrl) out.logoUrl = s.logoUrl;
        return out;
      });
    const outOfService = (await outages.list(b.id)).map((o) => ({ connectorId: o.connectorId, since: phIso(o.since) }));
    const body = { branchId: b.id, branchHours: b.hours, stores, outOfService };
    send(req, res, { ...body, generatedAt: phIso(new Date()) }, { tagOf: body, maxAge: 30 });
  } catch (err) {
    next(err);
  }
});

// ---- Posts: approved announcements live today, newest first, 10 per page ----

const cursorOf = (p) => Buffer.from(`${p.startsOn}|${p.id}|${p.branchId}`).toString('base64url');
function readCursor(text) {
  if (!text) return null;
  const m = /^(\d{4}-\d{2}-\d{2})\|(\d+)\|(\d+)$/.exec(Buffer.from(String(text), 'base64url').toString('utf8'));
  if (!m) throw new AppError(400, 'That page link is not valid.');
  return { startsOn: m[1], id: Number(m[2]), branchId: Number(m[3]) };
}
/** Newest first by start date, then id, then branch: a stable order for paging. */
const newerFirst = (a, b) => (a.startsOn < b.startsOn ? 1 : a.startsOn > b.startsOn ? -1 : b.id - a.id || a.branchId - b.branchId);

shopperRouter.get('/posts', async (req, res, next) => {
  try {
    const all = req.query.scope === 'all';
    const branches = await shopper.publishedBranches();
    let wanted = branches;
    if (!all) {
      const b = await publishedBranch(req.query.branch);
      wanted = [b];
    }
    const byId = new Map(branches.map((b) => [b.id, b]));
    const today = phToday();
    const rows = await shopper.livePosts(
      wanted.map((b) => b.id),
      today,
    );
    const base = baseOf(req);
    const flat = [];
    for (const p of rows) {
      for (const branchId of p.branchIds) {
        if (!wanted.some((w) => w.id === branchId)) continue;
        const b = byId.get(branchId);
        const item = {
          id: p.id,
          title: p.title,
          body: p.body,
          author: p.storeId != null ? { kind: 'store', storeId: p.storeId, name: p.storeName } : { kind: 'mall', name: b.mallName },
          startsOn: p.startsOn,
          endsOn: p.endsOn,
          branch: { id: b.id, name: b.name, mallName: b.mallName },
        };
        const imageUrl = p.imageKey ? `${base}/api/shopper/pictures/${p.imageKey}` : p.imageUrl;
        if (imageUrl) item.imageUrl = imageUrl;
        flat.push({ item, startsOn: p.startsOn, id: p.id, branchId });
      }
    }
    flat.sort(newerFirst);
    const after = readCursor(req.query.cursor);
    const start = after ? flat.findIndex((x) => newerFirst(x, after) > 0) : 0;
    const page = start < 0 ? [] : flat.slice(start, start + POSTS_PER_PAGE);
    const more = start >= 0 && start + POSTS_PER_PAGE < flat.length;
    const body = { items: page.map((x) => x.item), nextCursor: more ? cursorOf(page[page.length - 1]) : null };
    send(req, res, body, { maxAge: 60 });
  } catch (err) {
    next(err);
  }
});

/** An announcement's picture, public only while its post is approved and not over. */
shopperRouter.get('/pictures/:key', async (req, res, next) => {
  try {
    if (!/^[0-9a-f]{32}$/.test(req.params.key)) throw new AppError(404, 'Picture not found.');
    const pic = await shopper.livePicture(req.params.key, phToday());
    if (!pic || !pictures.has(pic.key, pic.mime)) throw new AppError(404, 'Picture not found.');
    res.set('Content-Type', pic.mime);
    res.set('Cache-Control', 'public, max-age=86400, immutable');
    pictures.stream(pic.key, pic.mime).pipe(res);
  } catch (err) {
    next(err);
  }
});

// ---- Anonymous counts (§9): no person, device or IP is kept with them ----

const countEvent = z.object({
  type: z.string(),
  branchId: z.number().int(),
  storeId: z.number().int().nullable().optional(),
  placeId: z.string().max(40).nullable().optional(),
  category: z.string().max(30).nullable().optional(),
  query: z.string().max(200).nullable().optional(),
  day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  n: z.number().int(),
});

/** The phone's search-word rules again (trimmed, lower case, ≤ 40, no emails, no 4+ digit runs); null to drop. */
function cleanQuery(q) {
  const t = String(q ?? '').trim().toLowerCase().replace(/\s+/g, ' ').slice(0, 40);
  if (!t || /\S+@\S+/.test(t) || /\d{4,}/.test(t.replace(/[\s-]/g, ''))) return null;
  return t;
}

shopperRouter.post('/counts', async (req, res, next) => {
  try {
    if (Buffer.byteLength(JSON.stringify(req.body ?? {})) > MAX_COUNT_BYTES) throw new AppError(413, 'Too many counts at once.');
    const events = Array.isArray(req.body?.events) ? req.body.events : null;
    if (!events) throw new AppError(400, 'Send {events: [...]}.');
    if (events.length > MAX_EVENTS) throw new AppError(413, `Send at most ${MAX_EVENTS} counts at once.`);
    const today = phToday();
    const oldest = addDays(today, -30);
    const newest = addDays(today, 1);
    const branches = new Map((await shopper.publishedBranches()).map((b) => [b.id, b]));
    const storesByBranch = new Map();
    const rows = [];
    for (const raw of events) {
      const parsed = countEvent.safeParse(raw);
      if (!parsed.success) continue;
      const e = parsed.data;
      if (!COUNT_TYPES.includes(e.type) || e.n < 1 || e.n > 10000 || e.day < oldest || e.day > newest || !branches.has(e.branchId)) continue;
      let storeId = e.storeId ?? null;
      if (storeId != null) {
        if (!storesByBranch.has(e.branchId)) storesByBranch.set(e.branchId, new Set((await shopper.storesOf([e.branchId])).map((s) => s.id)));
        if (!storesByBranch.get(e.branchId).has(storeId)) storeId = null;
      }
      let dim = '';
      if (e.type === 'search') {
        dim = cleanQuery(e.query);
        if (!dim) continue;
      } else if (e.type === 'category_tap') {
        dim = String(e.category ?? '').trim().toLowerCase().slice(0, 30);
      } else if (e.placeId && /^[A-Za-z0-9_-]{1,40}$/.test(e.placeId)) {
        dim = e.placeId;
      }
      rows.push({ day: e.day, branchId: e.branchId, event: e.type, storeId, dim, n: e.n });
    }
    if (rows.length) await shopper.addCounts(rows);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

shopperRouter.get('/app-config', async (req, res, next) => {
  try {
    const below = await settings.getNumber('app_must_update_below');
    res.set('Cache-Control', 'no-store');
    res.json({ mustUpdateBelow: below > 0 ? below : null, serverTime: phIso(new Date()), formatVersion: FORMAT_VERSION });
  } catch (err) {
    next(err);
  }
});
