// Round 21 (P1-07): the public shopper service and the web additions behind it
// (owner decisions 2026-10-23; contract docs/shopper-package-format.md §7–§11):
// directory, live store info, posts, pictures, anonymous counts, app config,
// hours, store status (also by the store owner), App category, the branch's
// Google Maps link, and lifts or escalators out of service.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';
import * as shopper from '../src/repos/shopper.js';
import { setFetchForTests } from '../src/utils/mapsLink.js';
import { phToday, addDays } from '../src/utils/dates.js';

const tag = `sh${Date.now().toString(36)}`;
let server;
let base;
let call;
let fx;
const tokens = {};
let category;

/** A public request: no token, raw response for headers and 304s. */
async function pub(method, path, { body, headers = {} } = {}) {
  const res = await fetch(`${base}/shopper${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = res.status === 204 || res.status === 304 ? '' : await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, body: json, headers: res.headers };
}

function png(w = 4, h = 3) {
  const p = new PNG({ width: w, height: h });
  p.data.fill(200);
  return PNG.sync.write(p);
}

async function upload(path, token, bytes, name = 'pic.png') {
  const form = new FormData();
  form.append('file', new Blob([bytes]), name);
  const res = await fetch(`${base}${path}`, { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form });
  return { status: res.status, body: await res.json() };
}

/** Publishes branch A's map: two levels joined by a lift, Unit 1 and Unit 2 on the ground floor. */
async function publishMap({ withLift = true } = {}) {
  const t = tokens.mall_admin;
  const existing = await call('GET', `/maps/${fx.branchA}`, { token: t });
  if (!existing.body?.map) assert.equal((await call('POST', `/maps/${fx.branchA}`, { token: t, body: { width: 40, depth: 30 } })).status, 201);
  assert.equal((await call('POST', `/maps/${fx.branchA}/lock`, { token: t })).status, 200);
  const get = await call('GET', `/maps/${fx.branchA}`, { token: t });
  const layout = get.body.map.draft;
  const ground = layout.buildings[0].levels[0];
  ground.features = [{ id: 'ft-e', type: 'entrance', x: 1, z: 15 }];
  ground.spaces = [
    { id: 'sp-1', name: 'Unit 1', type: 'retail', shape: { outer: [[10, 2], [16, 2], [16, 8], [10, 8]], holes: [] } },
    { id: 'sp-2', name: 'Unit 2', type: 'retail', shape: { outer: [[20, 2], [26, 2], [26, 8], [20, 8]], holes: [] } },
  ];
  layout.buildings[0].levels = [ground];
  layout.connectors = [];
  if (withLift) {
    layout.buildings[0].levels.push({ id: 'lv-two', name: 'Level 2', elevation: 5, height: 4, offset: [0, 0], rot: 0, outline: { outer: [[0, 0], [40, 0], [40, 30], [0, 30]], holes: [] }, walls: [], openings: [], spaces: [], features: [] });
    layout.connectors = [{ id: 'cn-lift', kind: 'elevator', name: 'West lifts', endpoints: [{ level: 'lv-ground', x: 30, z: 20 }, { level: 'lv-two', x: 30, z: 20 }] }];
  }
  const save = await call('PUT', `/maps/${fx.branchA}/draft`, { token: t, body: { layout, baseVersion: get.body.map.draftVersion } });
  assert.equal(save.status, 200, JSON.stringify(save.body));
  const published = await call('POST', `/maps/${fx.branchA}/publish`, { token: t, body: { baseVersion: save.body.draftVersion } });
  assert.equal(published.status, 200, JSON.stringify(published.body));
  await call('POST', `/maps/${fx.branchA}/lock/release`, { token: t });
  return published.body;
}

before(async () => {
  const s = await startServer();
  server = s.server;
  base = s.base;
  call = api(s.base);
  fx = await makeFixtures(tag);
  for (const role of ['superadmin', 'supervisor', 'mall_admin', 'store_owner']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
  // Store A: a category the phone sees as Fashion, linked to Unit 1.
  category = (await call('POST', '/options', { token: tokens.mall_admin, body: { branchId: fx.branchA, kind: 'store_category', name: `Clothes ${tag}` } })).body.option;
  await call('PUT', `/stores/${fx.storeA}`, { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `Store A ${tag}`, categoryId: category.id, openingHours: '10am-9pm daily', contactPhone: '+63 2 5550 0101', contactEmail: `shop.${tag}@test.local`, description: 'Clothes for everyone' } });
  assert.equal((await call('PUT', `/stores/${fx.storeA}/spaces`, { token: tokens.mall_admin, body: { spaceKeys: ['sp-1'] } })).status, 200);
  await publishMap();
});

after(async () => {
  setFetchForTests(null);
  await cleanFixtures(tag);
  await stopServer(server);
});

const HOURS = {
  week: [
    { day: 1, open: '10:00', close: '21:00' },
    { day: 6, open: '10:00', close: '24:00' },
    { day: 7, open: '22:00', close: '02:00' },
  ],
  specials: [{ date: '2026-12-25', closed: true, note: 'Holiday' }],
};

test('App category: set on a store category, refused on other kinds, audited', async () => {
  const set = await call('PUT', `/options/${category.id}/app-category`, { token: tokens.mall_admin, body: { appCategory: 'fashion' } });
  assert.equal(set.status, 200);
  assert.equal(set.body.option.appCategory, 'fashion');
  const label = (await call('POST', '/options', { token: tokens.mall_admin, body: { branchId: fx.branchA, kind: 'floor_label', name: `F${tag}` } })).body.option;
  assert.equal((await call('PUT', `/options/${label.id}/app-category`, { token: tokens.mall_admin, body: { appCategory: 'food' } })).status, 400);
  assert.equal((await call('PUT', `/options/${category.id}/app-category`, { token: tokens.mall_admin, body: { appCategory: 'toys' } })).status, 400);
  assert.equal((await call('PUT', `/options/${category.id}/app-category`, { token: tokens.store_owner, body: { appCategory: 'food' } })).status, 403);
  assert.ok((await db.auditRows({ action: 'option_app_category_set', entityId: category.id })).length);
});

test('hours: checked, stored in order, set by the mall admin on branches and stores', async () => {
  const bad = await call('PUT', `/stores/${fx.storeA}/hours`, { token: tokens.mall_admin, body: { hours: { week: [{ day: 1, open: '9am', close: '21:00' }] } } });
  assert.equal(bad.status, 400);
  const twice = await call('PUT', `/stores/${fx.storeA}/hours`, { token: tokens.mall_admin, body: { hours: { week: [{ day: 1, open: '09:00', close: '12:00' }, { day: 1, open: '13:00', close: '18:00' }] } } });
  assert.equal(twice.status, 400, 'one range per day');
  const shuffled = { week: [...HOURS.week].reverse(), specials: HOURS.specials };
  const ok = await call('PUT', `/branches/${fx.branchA}/hours`, { token: tokens.mall_admin, body: { hours: shuffled } });
  assert.equal(ok.status, 200);
  assert.deepEqual(ok.body.branch.hours, HOURS);
  const owner = await call('PUT', `/branches/${fx.branchA}/hours`, { token: tokens.supervisor, body: { hours: HOURS } });
  assert.equal(owner.status, 200, 'the mall owner edits branch info too');
  assert.equal((await call('PUT', `/branches/${fx.branchB}/hours`, { token: tokens.mall_admin, body: { hours: HOURS } })).status, 403);
  assert.ok((await db.auditRows({ action: 'branch_hours_updated', entityId: fx.branchA })).length);
});

test('store status and hours: the mall admin, and the store owner for their own active store only', async () => {
  const s1 = await call('PUT', `/stores/${fx.storeA}/status`, { token: tokens.store_owner, body: { status: 'being_repaired' } });
  assert.equal(s1.status, 200);
  assert.equal(s1.body.store.status, 'being_repaired');
  const h = await call('PUT', `/stores/${fx.storeA}/hours`, { token: tokens.store_owner, body: { hours: { week: [{ day: 2, open: '11:00', close: '20:00' }] } } });
  assert.equal(h.status, 200);
  assert.deepEqual(h.body.store.hours, { week: [{ day: 2, open: '11:00', close: '20:00' }], specials: [] });
  // Not their store.
  const other = (await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `Other ${tag}` } })).body.store;
  assert.equal((await call('PUT', `/stores/${other.id}/status`, { token: tokens.store_owner, body: { status: 'open' } })).status, 403);
  // The owner still cannot change other details.
  assert.equal((await call('PUT', `/stores/${fx.storeA}`, { token: tokens.store_owner, body: { branchId: fx.branchA, name: 'Renamed' } })).status, 403);
  assert.equal((await call('PUT', `/stores/${fx.storeA}/status`, { token: tokens.store_owner, body: { status: 'closed_forever' } })).status, 400);
  const back = await call('PUT', `/stores/${fx.storeA}/status`, { token: tokens.mall_admin, body: { status: 'open' } });
  assert.equal(back.body.store.status, 'open');
  const audit = await db.auditRows({ action: 'store_status_changed', entityId: fx.storeA });
  assert.equal(audit.length, 2);
  assert.match(audit[0].details, /"byRole":"store_owner"/);
});

test('directory: published branches of active malls, with their stores, App categories and floors', async () => {
  await call('PUT', `/options/${category.id}/app-category`, { token: tokens.mall_admin, body: { appCategory: 'fashion' } });
  const r = await pub('GET', '/directory');
  assert.equal(r.status, 200);
  const a = r.body.branches.find((b) => b.id === fx.branchA);
  assert.ok(a, 'branch A is published');
  assert.equal(a.mallId, fx.mallA);
  assert.equal(a.mallName, `Mall A ${tag}`);
  assert.equal(a.active, true);
  // Step B (P1-08) builds the package at publish; its details are checked in the package test below.
  assert.equal(a.package.formatVersion, 1, 'the package built at publish');
  assert.deepEqual(
    a.stores.find((s) => s.storeId === fx.storeA),
    { storeId: fx.storeA, name: `Store A ${tag}`, category: 'fashion', floor: 'G' },
  );
  assert.ok(!a.stores.some((s) => s.name.startsWith('Other')), 'a store with no space on the map is not listed');
  assert.ok(!r.body.branches.some((b) => b.id === fx.branchB), 'a branch without a published map is not listed');
  assert.ok(!JSON.stringify(r.body).includes('@test.local'), 'no emails');
  // ETag and 304.
  const again = await pub('GET', '/directory', { headers: { 'If-None-Match': r.headers.get('etag') } });
  assert.equal(again.status, 304);
});

test('live: store info by space, branch hours, the old hours note, 404 for unknown or unpublished branches', async () => {
  await call('PUT', `/stores/${fx.storeA}/hours`, { token: tokens.mall_admin, body: { hours: null } });
  const r = await pub('GET', `/branches/${fx.branchA}/live`);
  assert.equal(r.status, 200);
  assert.equal(r.body.branchId, fx.branchA);
  assert.match(r.body.generatedAt, /\+08:00$/);
  assert.deepEqual(r.body.branchHours, HOURS);
  const s = r.body.stores.find((x) => x.storeId === fx.storeA);
  assert.deepEqual(s, {
    storeId: fx.storeA,
    spaceIds: ['sp-1'],
    name: `Store A ${tag}`,
    category: 'fashion',
    status: 'open',
    hours: null,
    hoursNote: '10am-9pm daily',
    phone: '+63 2 5550 0101',
    description: 'Clothes for everyone',
  });
  assert.ok(!JSON.stringify(r.body).includes('@test.local'), 'no emails');
  assert.deepEqual(r.body.outOfService, []);
  const same = await pub('GET', `/branches/${fx.branchA}/live`, { headers: { 'If-None-Match': r.headers.get('etag') } });
  assert.equal(same.status, 304, 'unchanged info answers 304 even though generatedAt moves');
  assert.equal((await pub('GET', `/branches/${fx.branchB}/live`)).status, 404);
  assert.equal((await pub('GET', '/branches/999999999/live')).status, 404);
  assert.equal((await pub('GET', '/branches/abc/live')).status, 404);
  // A deactivated store disappears.
  await call('POST', `/stores/${fx.storeA}/deactivate`, { token: tokens.mall_admin });
  const without = await pub('GET', `/branches/${fx.branchA}/live`);
  assert.ok(!without.body.stores.some((x) => x.storeId === fx.storeA));
  await call('POST', `/stores/${fx.storeA}/reactivate`, { token: tokens.mall_admin });
});

test('out of service: mall admins mark a lift from the published map; it reaches /live; a republish without it clears the mark', async () => {
  const list = await call('GET', `/maps/${fx.branchA}/connectors`, { token: tokens.supervisor });
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.items.map((c) => [c.id, c.kind, c.name, c.outOfService]), [['cn-lift', 'elevator', 'West lifts', false]]);
  assert.equal((await call('PUT', `/maps/${fx.branchA}/connectors/cn-lift/out-of-service`, { token: tokens.supervisor, body: { out: true } })).status, 403);
  assert.equal((await call('PUT', `/maps/${fx.branchA}/connectors/cn-nope/out-of-service`, { token: tokens.mall_admin, body: { out: true } })).status, 404);
  const mark = await call('PUT', `/maps/${fx.branchA}/connectors/cn-lift/out-of-service`, { token: tokens.mall_admin, body: { out: true } });
  assert.equal(mark.status, 200);
  assert.equal(mark.body.items[0].outOfService, true);
  const live = await pub('GET', `/branches/${fx.branchA}/live`);
  assert.deepEqual(live.body.outOfService.map((o) => o.connectorId), ['cn-lift']);
  assert.match(live.body.outOfService[0].since, /\+08:00$/);
  assert.ok((await db.auditRows({ action: 'connector_out_of_service', entityId: fx.branchA })).length);

  await publishMap({ withLift: false });
  const after = await pub('GET', `/branches/${fx.branchA}/live`);
  assert.deepEqual(after.body.outOfService, []);
  const cleared = await db.auditRows({ action: 'connector_marks_cleared', entityId: fx.branchA });
  assert.match(cleared[0].details, /cn-lift/);
  await publishMap();
});

test('posts: approved and live today, newest first, 10 per page with a cursor; pending, rejected and expired never sent', async () => {
  const today = phToday();
  const made = [];
  for (let i = 0; i < 11; i++) {
    const r = await call('POST', '/announcements', { token: tokens.mall_admin, body: { title: `Post ${i} ${tag}`, body: 'Hello', startsOn: addDays(today, -(i % 3)), endsOn: addDays(today, 2), branchIds: [fx.branchA] } });
    assert.equal(r.status, 201);
    made.push(r.body.announcement.id);
  }
  const pending = await call('POST', '/announcements', { token: tokens.store_owner, body: { title: `Pending ${tag}`, body: 'x', startsOn: today, endsOn: today, storeId: fx.storeA } });
  const later = await call('POST', '/announcements', { token: tokens.mall_admin, body: { title: `Later ${tag}`, body: 'x', startsOn: addDays(today, 3), endsOn: addDays(today, 4), branchIds: [fx.branchA] } });

  const p1 = await pub('GET', `/posts?branch=${fx.branchA}`);
  assert.equal(p1.status, 200);
  const mine = (items) => items.filter((x) => x.title.endsWith(tag));
  assert.equal(p1.body.items.length, 10);
  assert.ok(p1.body.nextCursor);
  const p2 = await pub('GET', `/posts?branch=${fx.branchA}&cursor=${encodeURIComponent(p1.body.nextCursor)}`);
  const all = mine([...p1.body.items, ...p2.body.items]);
  assert.equal(all.length, 11);
  assert.ok(!all.some((x) => x.title.startsWith('Pending') || x.title.startsWith('Later')));
  for (let i = 1; i < all.length; i++) {
    const [a, b] = [all[i - 1], all[i]];
    assert.ok(a.startsOn > b.startsOn || (a.startsOn === b.startsOn && a.id > b.id), 'newest first');
  }
  const first = all[0];
  assert.deepEqual(first.author, { kind: 'mall', name: `Mall A ${tag}` });
  assert.deepEqual(first.branch, { id: fx.branchA, name: `Branch A ${tag}`, mallName: `Mall A ${tag}` });
  assert.ok(!('reviewedBy' in first) && !('status' in first));
  const same = await pub('GET', `/posts?branch=${fx.branchA}`, { headers: { 'If-None-Match': p1.headers.get('etag') } });
  assert.equal(same.status, 304);
  // Approved store-owner post: author is the store.
  await call('POST', `/announcements/${pending.body.announcement.id}/approve`, { token: tokens.mall_admin });
  const withStore = await pub('GET', '/posts?scope=all');
  const sp = withStore.body.items.find((x) => x.id === pending.body.announcement.id) ?? (await pub('GET', `/posts?scope=all&cursor=${encodeURIComponent(withStore.body.nextCursor)}`)).body.items.find((x) => x.id === pending.body.announcement.id);
  assert.deepEqual(sp?.author, { kind: 'store', storeId: fx.storeA, name: `Store A ${tag}` });
  assert.equal((await pub('GET', `/posts?branch=${fx.branchB}`)).status, 404);
  assert.equal((await pub('GET', `/posts?branch=${fx.branchA}&cursor=nonsense`)).status, 400);
  for (const id of [...made, later.body.announcement.id, pending.body.announcement.id]) await call('DELETE', `/announcements/${id}`, { token: tokens.mall_admin });
});

test('pictures: one PNG or JPEG up to 2 MB replaces the link; public only while the post is approved', async () => {
  const today = phToday();
  const ann = (await call('POST', '/announcements', { token: tokens.mall_admin, body: { title: `Pic ${tag}`, body: 'x', startsOn: today, endsOn: today, branchIds: [fx.branchA] } })).body.announcement;
  assert.equal((await upload(`/announcements/${ann.id}/picture`, tokens.mall_admin, Buffer.from('not a picture'), 'a.txt')).status, 400);
  assert.equal((await upload(`/announcements/${ann.id}/picture`, tokens.mall_admin, Buffer.alloc(2 * 1024 * 1024 + 10, 1))).status, 400);
  const up = await upload(`/announcements/${ann.id}/picture`, tokens.mall_admin, png());
  assert.equal(up.status, 200, JSON.stringify(up.body));
  const key = up.body.announcement.imageKey;
  assert.match(key, /^[0-9a-f]{32}$/);
  const posts = await pub('GET', `/posts?branch=${fx.branchA}`);
  const item = posts.body.items.find((x) => x.id === ann.id);
  assert.equal(item.imageUrl, `${base}/shopper/pictures/${key}`);
  const img = await fetch(item.imageUrl);
  assert.equal(img.status, 200);
  assert.equal(img.headers.get('content-type'), 'image/png');
  const admin = await fetch(`${base}/announcements/${ann.id}/picture`, { headers: { Authorization: `Bearer ${tokens.supervisor}` } });
  assert.equal(admin.status, 200);
  // A store owner's submission with a picture is not public until approved; changing it sends it back for review.
  const sub = (await call('POST', '/announcements', { token: tokens.store_owner, body: { title: `Sub ${tag}`, body: 'x', startsOn: today, endsOn: today, storeId: fx.storeA } })).body.announcement;
  const subUp = await upload(`/announcements/${sub.id}/picture`, tokens.store_owner, png());
  assert.equal(subUp.status, 200);
  assert.equal((await fetch(`${base}/shopper/pictures/${subUp.body.announcement.imageKey}`)).status, 404);
  await call('POST', `/announcements/${sub.id}/approve`, { token: tokens.mall_admin });
  assert.equal((await fetch(`${base}/shopper/pictures/${subUp.body.announcement.imageKey}`)).status, 200);
  const again = await upload(`/announcements/${sub.id}/picture`, tokens.store_owner, png(5, 5));
  assert.equal(again.body.announcement.status, 'pending');
  assert.equal((await upload(`/announcements/${sub.id}/picture`, tokens.supervisor, png())).status, 403, 'mall owners do not change store-owner submissions');
  const removed = await call('DELETE', `/announcements/${ann.id}/picture`, { token: tokens.mall_admin });
  assert.equal(removed.body.announcement.imageKey, null);
  assert.equal((await fetch(`${base}/shopper/pictures/${key}`)).status, 404);
  for (const id of [ann.id, sub.id]) await call('DELETE', `/announcements/${id}`, { token: tokens.mall_admin });
});

test('counts: added up per day by branch, event, store and detail; bad events dropped; caps', async () => {
  const day = phToday();
  const r = await pub('POST', '/counts', {
    body: {
      events: [
        { type: 'place_opened', branchId: fx.branchA, storeId: fx.storeA, placeId: 'sp-1', day, n: 3 },
        { type: 'place_opened', branchId: fx.branchA, storeId: fx.storeA, placeId: 'sp-1', day, n: 2 },
        { type: 'category_tap', branchId: fx.branchA, category: 'Food', day, n: 5 },
        { type: 'search', branchId: fx.branchA, query: '  Uniqlo ', day, n: 2 },
        { type: 'search', branchId: fx.branchA, query: 'me@mail.com', day, n: 1 },
        { type: 'search', branchId: fx.branchA, query: 'call 0917 555 1234', day, n: 1 },
        { type: 'mall_opened', branchId: fx.branchA, day: addDays(day, -40), n: 1 },
        { type: 'mall_opened', branchId: fx.branchB, day, n: 1 },
        { type: 'teleported', branchId: fx.branchA, day, n: 1 },
        { type: 'directions_started', branchId: fx.branchA, storeId: 999999999, day, n: 1 },
        { type: 'mall_opened', branchId: fx.branchA, day, n: 0 },
      ],
    },
  });
  assert.equal(r.status, 204);
  const totals = await shopper.countsOf(fx.branchA);
  const pick = (event, dim) => totals.filter((t) => t.event === event && t.dim === dim).reduce((a, t) => a + t.n, 0);
  assert.equal(pick('place_opened', 'sp-1'), 5);
  assert.equal(totals.find((t) => t.event === 'place_opened').storeId, fx.storeA);
  assert.equal(pick('category_tap', 'food'), 5);
  assert.equal(pick('search', 'uniqlo'), 2);
  assert.equal(totals.filter((t) => t.event === 'search').length, 1, 'emails and phone numbers dropped');
  assert.equal(totals.filter((t) => t.event === 'mall_opened').length, 0, 'too old, unknown branch or zero dropped');
  assert.equal(totals.find((t) => t.event === 'directions_started')?.storeId ?? null, null, 'a store not in the branch is dropped from the count');
  assert.equal((await shopper.countsOf(fx.branchB)).length, 0);
  const tooMany = await pub('POST', '/counts', { body: { events: Array.from({ length: 501 }, () => ({ type: 'mall_opened', branchId: fx.branchA, day, n: 1 })) } });
  assert.equal(tooMany.status, 413);
  assert.equal((await pub('POST', '/counts', { body: { nothing: true } })).status, 400);
  assert.equal((await db.auditRows({ actionPrefix: 'POST /api/shopper' })).length, 0, 'never audited');
});

test('app-config: the oldest allowed build (a superadmin setting), Philippine server time, the format version', async () => {
  const a = await pub('GET', '/app-config');
  assert.equal(a.status, 200);
  assert.equal(a.body.formatVersion, 1);
  assert.match(a.body.serverTime, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+08:00$/);
  const before = a.body.mustUpdateBelow;
  await db.setSetting('app_must_update_below', 120);
  try {
    assert.equal((await pub('GET', '/app-config')).body.mustUpdateBelow, 120);
  } finally {
    await db.setSetting('app_must_update_below', before ?? 0);
  }
  assert.equal((await pub('GET', '/app-config')).body.mustUpdateBelow, before);
});

test('branch location: a pasted Google Maps link, short links followed once; the place name shown back; bad links refused', async () => {
  const full = 'https://www.google.com/maps/place/SM+North+EDSA/@14.6566,121.0291,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d14.656912!4d121.030141';
  const seen = [];
  setFetchForTests(async (url) => {
    seen.push(url);
    return { headers: new Map([['location', full]]) };
  });
  const check = await call('POST', `/branches/${fx.branchA}/location/check`, { token: tokens.mall_admin, body: { mapsLink: 'https://maps.app.goo.gl/AbCdEf123' } });
  assert.equal(check.status, 200, JSON.stringify(check.body));
  assert.equal(check.body.placeName, 'SM North EDSA');
  assert.deepEqual(seen, ['https://maps.app.goo.gl/AbCdEf123']);
  const save = await call('PUT', `/branches/${fx.branchA}/location`, { token: tokens.mall_admin, body: { mapsLink: full } });
  assert.equal(save.status, 200);
  assert.equal(save.body.branch.placeName, 'SM North EDSA');
  assert.equal(save.body.branch.latitude, 14.656912, 'the place pin wins over the view centre');
  assert.equal(save.body.branch.longitude, 121.030141);
  const dir = await pub('GET', '/directory');
  const a = dir.body.branches.find((b) => b.id === fx.branchA);
  assert.deepEqual([a.lat, a.lng], [14.656912, 121.030141]);
  for (const bad of ['not a link', 'https://example.com/maps/place/x/@1,2', 'https://www.google.com/maps/search/coffee']) {
    assert.equal((await call('POST', `/branches/${fx.branchA}/location/check`, { token: tokens.mall_admin, body: { mapsLink: bad } })).status, 400, bad);
  }
  setFetchForTests(async () => ({ headers: new Map([['location', 'https://evil.example/maps/place/x/@1,2']]) }));
  assert.equal((await call('POST', `/branches/${fx.branchA}/location/check`, { token: tokens.mall_admin, body: { mapsLink: 'https://maps.app.goo.gl/x' } })).status, 400);
  assert.equal((await call('PUT', `/branches/${fx.branchA}/location`, { token: tokens.store_owner, body: { mapsLink: full } })).status, 403);
  assert.ok((await db.auditRows({ action: 'branch_location_updated', entityId: fx.branchA })).length);
});

// ---- Round 21 step B (P1-08): the shopper package built at publish, and the gate ----

test('publishing builds the package: listed in the directory, downloaded with its checksum, 304 when unchanged', async () => {
  const dir = await pub('GET', '/directory');
  const a = dir.body.branches.find((b) => b.id === fx.branchA);
  assert.ok(a.package, 'the directory lists the package');
  assert.equal(a.package.formatVersion, 1);
  assert.match(a.package.checksum, /^[0-9a-f]{64}$/);
  const res = await fetch(`${base}/shopper/branches/${fx.branchA}/package?version=${a.package.version}`, { headers: { 'Accept-Encoding': 'gzip' } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('x-package-checksum'), a.package.checksum);
  assert.equal(res.headers.get('etag'), `"${a.package.checksum}"`);
  const bytes = Buffer.from(await res.arrayBuffer());
  const { createHash } = await import('node:crypto');
  assert.equal(createHash('sha256').update(bytes).digest('hex'), a.package.checksum, 'the checksum is of the un-gzipped bytes');
  assert.equal(bytes.length, a.package.sizeBytes);
  const pkg = JSON.parse(bytes.toString('utf8'));
  assert.equal(pkg.formatVersion, 1);
  assert.equal(pkg.version, a.package.version);
  assert.equal(pkg.branchId, fx.branchA);
  assert.match(pkg.publishedAt, /\+08:00$/);
  assert.ok(pkg.places.some((p) => p.id === 'sp-1' && p.storeId === fx.storeA));
  assert.ok(pkg.connectors.some((c) => c.id === 'cn-lift' && c.type === 'lift'));
  const same = await fetch(`${base}/shopper/branches/${fx.branchA}/package?version=${a.package.version}`, { headers: { 'If-None-Match': `"${a.package.checksum}"` } });
  assert.equal(same.status, 304);
  assert.equal((await fetch(`${base}/shopper/branches/${fx.branchA}/package?version=999`)).status, 404);
  assert.equal((await fetch(`${base}/shopper/branches/${fx.branchB}/package`)).status, 404);
});

test('the gate: a dry run says what blocks publishing, publishing is refused with the space to select, and passes once fixed', async () => {
  const t = tokens.mall_admin;
  const ok = await call('POST', `/maps/${fx.branchA}/publish-check`, { token: t });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.ready, true);
  // A walled shop with no door, linked to Store A.
  assert.equal((await call('POST', `/maps/${fx.branchA}/lock`, { token: t })).status, 200);
  const get = await call('GET', `/maps/${fx.branchA}`, { token: t });
  const layout = get.body.map.draft;
  const ground = layout.buildings[0].levels[0];
  ground.walls = [
    { id: 'w1', a: [10, 2], b: [16, 2], t: 0.2 },
    { id: 'w2', a: [16, 2], b: [16, 8], t: 0.2 },
    { id: 'w3', a: [16, 8], b: [10, 8], t: 0.2 },
    { id: 'w4', a: [10, 8], b: [10, 2], t: 0.2 },
  ];
  const save = await call('PUT', `/maps/${fx.branchA}/draft`, { token: t, body: { layout, baseVersion: get.body.map.draftVersion } });
  assert.equal(save.status, 200);
  const check = await call('POST', `/maps/${fx.branchA}/publish-check`, { token: t });
  assert.equal(check.body.ready, false);
  assert.deepEqual(check.body.problems, [`Store A ${tag} (Unit 1) can't be reached: it has no door to a corridor`]);
  assert.deepEqual(check.body.problemDetails[0].ids, ['sp-1']);
  const refused = await call('POST', `/maps/${fx.branchA}/publish`, { token: t, body: { baseVersion: save.body.draftVersion } });
  assert.equal(refused.status, 400);
  assert.deepEqual(refused.body.problems, check.body.problems);
  assert.equal(refused.body.problemDetails[0].code, 'unreachable');
  // A door fixes it.
  ground.openings = [{ id: 'op-1', wall: 'w3', at: 0.5, w: 1.2, kind: 'door' }];
  const save2 = await call('PUT', `/maps/${fx.branchA}/draft`, { token: t, body: { layout, baseVersion: save.body.draftVersion } });
  const pubd = await call('POST', `/maps/${fx.branchA}/publish`, { token: t, body: { baseVersion: save2.body.draftVersion } });
  assert.equal(pubd.status, 200, JSON.stringify(pubd.body));
  assert.equal(pubd.body.packageError, null);
  assert.ok(Array.isArray(pubd.body.shopperWarnings));
  await call('POST', `/maps/${fx.branchA}/lock/release`, { token: t });
  // The mall owner cannot run the check.
  assert.equal((await call('POST', `/maps/${fx.branchA}/publish-check`, { token: tokens.supervisor })).status, 403);
  // The directory points at the new version's package.
  const dir = await pub('GET', '/directory');
  assert.equal(dir.body.branches.find((b) => b.id === fx.branchA).package.version, pubd.body.publishedVersion);
});
