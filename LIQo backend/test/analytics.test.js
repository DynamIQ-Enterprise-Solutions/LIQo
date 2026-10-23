// US-005 / US-015 / US-023: the analytics report is scoped like the lists and
// counts what the fixtures contain.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `a${Date.now().toString(36)}`;
let server;
let call;
let fx;
const tokens = {};

before(async () => {
  const s = await startServer();
  server = s.server;
  call = api(s.base);
  fx = await makeFixtures(tag);
  for (const role of ['superadmin', 'supervisor', 'mall_admin', 'store_owner']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
});

after(async () => {
  await cleanFixtures(tag);
  await stopServer(server);
});

const today = new Date().toISOString().slice(0, 10);

test('days must be 7, 30 or 90; 7 returns seven zero-filled rows ending today', async () => {
  const bad = await call('GET', '/analytics/report?days=365', { token: tokens.superadmin });
  assert.equal(bad.status, 400);
  const ok = await call('GET', '/analytics/report?days=7', { token: tokens.superadmin });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.activity.days.length, 7);
  assert.equal(ok.body.activity.days[6].date, ok.body.to);
  for (const row of ok.body.activity.days) for (const k of ['logins', 'submitted', 'published', 'mapPublications', 'mapEdits']) assert.equal(typeof row[k], 'number');
});

test('superadmin: a store, an announcement, a map save and a publish show up today in the right sections', async () => {
  const store = await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `Analytics Store ${tag}` } });
  assert.equal(store.status, 201);
  const ann = await call('POST', '/announcements', {
    token: tokens.store_owner,
    body: { title: `Promo ${tag}`, body: 'x', startsOn: today, endsOn: today, storeId: fx.storeA },
  });
  assert.equal(ann.status, 201);

  const created = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { width: 20, depth: 20 } });
  assert.equal(created.status, 201);
  await call('POST', `/maps/${fx.branchA}/lock`, { token: tokens.mall_admin });
  const get = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  const layout = get.body.map.draft;
  layout.buildings[0].levels[0].features.push({ id: 'ft-e', type: 'entrance', x: 1, z: 0 });
  layout.buildings[0].levels[0].spaces.push({ id: 'sp-1', name: 'Unit 1', type: 'retail', shape: { outer: [[1, 1], [5, 1], [5, 5], [1, 5]], holes: [] } });
  const save = await call('PUT', `/maps/${fx.branchA}/draft`, { token: tokens.mall_admin, body: { layout, baseVersion: get.body.map.draftVersion } });
  assert.equal(save.status, 200);
  const pub = await call('POST', `/maps/${fx.branchA}/publish`, { token: tokens.mall_admin, body: { baseVersion: save.body.draftVersion } });
  assert.equal(pub.status, 200, JSON.stringify(pub.body));

  const r = await call('GET', '/analytics/report?days=7', { token: tokens.superadmin });
  assert.equal(r.status, 200);
  const todayRow = r.body.activity.days[6];
  assert.ok(todayRow.logins >= 4, 'the four fixture sign-ins count');
  assert.ok(todayRow.submitted >= 1);
  assert.ok(todayRow.mapEdits >= 1, 'an editing stretch is counted from the audit log');
  assert.ok(todayRow.mapPublications >= 1);

  const branchRow = r.body.stores.byBranch.find((b) => b.branchId === fx.branchA);
  assert.equal(branchRow.active, 2, 'fixture store + the one created here');
  assert.equal(branchRow.withOwner, 1);
  assert.ok(r.body.stores.byCategory.some((c) => c.name === 'No category' && c.count >= 2));

  assert.ok(r.body.announcements.byStatus.pending >= 1);
  assert.ok(r.body.announcements.pending.some((p) => p.title === `Promo ${tag}` && p.waitingDays === 0 && p.role === 'store_owner'));

  const mapRow = r.body.maps.byBranch.find((b) => b.branchId === fx.branchA);
  assert.equal(mapRow.state, 'published');
  assert.equal(mapRow.versions, 1);
  assert.equal(mapRow.spaces, 1);
  assert.equal(mapRow.named, 1);
  const mapRowB = r.body.maps.byBranch.find((b) => b.branchId === fx.branchB);
  assert.equal(mapRowB.state, 'none');

  assert.ok(r.body.security, 'superadmin gets the security section');
  assert.ok(Array.isArray(r.body.security.topFailures));
  assert.ok(r.body.accounts.byRole.some((x) => x.role === 'superadmin'));
});

test('supervisor of mall A sees nothing from mall B and no security section', async () => {
  // A store and an announcement that live only in mall B.
  const storeB = await db.insertStore(fx.branchB, `Store B ${tag}`);
  const annB = await call('POST', '/announcements', {
    token: tokens.superadmin,
    body: { title: `Mall B only ${tag}`, body: 'x', startsOn: today, endsOn: today, branchIds: [fx.branchB] },
  });
  assert.equal(annB.status, 201, JSON.stringify(annB.body));

  const r = await call('GET', '/analytics/report?days=30', { token: tokens.supervisor });
  assert.equal(r.status, 200);
  assert.ok(r.body.stores.byBranch.every((b) => b.branchId !== fx.branchB));
  assert.ok(r.body.maps.byBranch.every((b) => b.branchId !== fx.branchB));
  assert.ok(r.body.announcements.byBranch.every((b) => b.branchId !== fx.branchB));
  assert.ok(r.body.announcements.pending.every((p) => p.title !== `Mall B only ${tag}`));
  assert.equal(r.body.security, null);
  assert.ok(r.body.accounts.byRole.every((x) => x.role === 'mall_admin' || x.role === 'store_owner'));
  void storeB;
});

test('mall admin: accounts are store owners only, map coverage is their branches only', async () => {
  const r = await call('GET', '/analytics/report?days=90', { token: tokens.mall_admin });
  assert.equal(r.status, 200);
  assert.equal(r.body.activity.days.length, 90);
  assert.ok(r.body.accounts.byRole.every((x) => x.role === 'store_owner'));
  assert.deepEqual(r.body.maps.byBranch.map((b) => b.branchId), [fx.branchA]);
  assert.equal(r.body.security, null);
});
