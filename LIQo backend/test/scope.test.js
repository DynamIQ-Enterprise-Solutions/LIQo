// US-046: each role cannot reach resources outside its scope, and
// unauthorized API operations are refused by the backend itself.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';

const tag = `s${Date.now().toString(36)}`;
let server;
let call;
let fx;
const tokens = {};

// Date-only strings for announcements that are still running.
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const today = () => ymd(new Date());
const inAYear = () => ymd(new Date(Date.now() + 365 * 86400000));

before(async () => {
  const s = await startServer();
  server = s.server;
  call = api(s.base);
  fx = await makeFixtures(tag);
  for (const role of ['superadmin', 'supervisor', 'mall_admin', 'store_owner']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    assert.equal(r.status, 200, `login ${role}`);
    tokens[role] = r.body.token;
  }
});

after(async () => {
  await cleanFixtures(tag);
  await stopServer(server);
});

// ---- Supervisor ----

test('supervisor sees only assigned malls and branches', async () => {
  const malls = await call('GET', '/malls?pageSize=100', { token: tokens.supervisor });
  assert.equal(malls.status, 200);
  const ids = malls.body.items.map((m) => m.id);
  assert.ok(ids.includes(fx.mallA));
  assert.ok(!ids.includes(fx.mallB));

  const branches = await call('GET', '/branches?pageSize=100', { token: tokens.supervisor });
  const bids = branches.body.items.map((b) => b.id);
  assert.ok(bids.includes(fx.branchA));
  assert.ok(!bids.includes(fx.branchB));
});

test('supervisor cannot open a mall outside scope', async () => {
  const r = await call('GET', `/malls/${fx.mallB}`, { token: tokens.supervisor });
  assert.equal(r.status, 403);
});

test('supervisor cannot create malls, read the audit log, or change settings', async () => {
  assert.equal((await call('POST', '/malls', { token: tokens.supervisor, body: { name: `X ${tag}` } })).status, 403);
  assert.equal((await call('GET', '/audit', { token: tokens.supervisor })).status, 403);
  assert.equal((await call('PUT', '/settings', { token: tokens.supervisor, body: { min_password_length: 9 } })).status, 403);
});

test('mall owner creates admins only inside their branches and sees only admins that report to them', async () => {
  const noBranch = await call('POST', '/accounts', { token: tokens.supervisor, body: { email: `new.${tag}@test.local`, fullName: 'New Person', role: 'mall_admin' } });
  assert.equal(noBranch.status, 400);
  const outside = await call('POST', '/accounts', {
    token: tokens.supervisor,
    body: { email: `new.${tag}@test.local`, fullName: 'New Person', role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchB] } },
  });
  assert.equal(outside.status, 403);
  const owner = await call('POST', '/accounts', { token: tokens.supervisor, body: { email: `new.${tag}@test.local`, fullName: 'New Person', role: 'supervisor' } });
  assert.equal(owner.status, 403);
  const list = await call('GET', '/accounts?pageSize=100', { token: tokens.supervisor });
  assert.equal(list.status, 200);
  assert.ok(list.body.items.every((u) => u.role === 'mall_admin' && u.reportsTo?.id === fx.supervisorId));
  assert.ok(list.body.items.some((u) => u.id === fx.mallAdminId));
});

test('supervisor cannot target a branch outside scope in an announcement', async () => {
  const r = await call('POST', '/announcements', {
    token: tokens.supervisor,
    body: { title: `Hello ${tag}`, body: 'x', startsOn: '2026-01-01', endsOn: '2026-01-02', branchIds: [fx.branchB] },
  });
  assert.equal(r.status, 403);
});

// ---- Mall admin ----

test('mall admin cannot touch a branch outside scope', async () => {
  assert.equal((await call('GET', `/branches/${fx.branchB}`, { token: tokens.mall_admin })).status, 403);
  assert.equal(
    (await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchB, name: `S ${tag}` } })).status,
    403,
  );
  assert.equal(
    (await call('POST', '/options', { token: tokens.mall_admin, body: { branchId: fx.branchB, kind: 'unit_type', name: `Kiosk ${tag}` } })).status,
    403,
  );
});

test('mall admin cannot create malls, branches, or supervisor accounts', async () => {
  assert.equal((await call('POST', '/malls', { token: tokens.mall_admin, body: { name: `Y ${tag}` } })).status, 403);
  assert.equal((await call('POST', '/branches', { token: tokens.mall_admin, body: { mallId: fx.mallA, name: `B ${tag}` } })).status, 403);
  assert.equal((await call('GET', '/accounts', { token: tokens.mall_admin })).status, 403);
});

test('mall admin can create a store in scope and a store owner sees only own stores', async () => {
  const created = await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `Store B ${tag}` } });
  assert.equal(created.status, 201);

  const mine = await call('GET', '/stores?pageSize=100', { token: tokens.store_owner });
  assert.equal(mine.status, 200);
  const ids = mine.body.items.map((s) => s.id);
  assert.ok(ids.includes(fx.storeA));
  assert.ok(!ids.includes(created.body.store.id));
  assert.equal((await call('GET', `/stores/${created.body.store.id}`, { token: tokens.store_owner })).status, 403);
});

// ---- Store owner ----

test('store owner cannot submit for a store that is not theirs, and cannot review', async () => {
  const other = await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `Store C ${tag}` } });
  const wrongStore = await call('POST', '/announcements', {
    token: tokens.store_owner,
    body: { title: `Nope ${tag}`, body: 'x', startsOn: '2026-01-01', endsOn: '2026-01-02', storeId: other.body.store.id },
  });
  assert.equal(wrongStore.status, 403);

  // Round 14 (D23, approved 2026-10-22): a new announcement cannot end in the past,
  // so this one ends a year from today instead of on a fixed past date.
  const ok = await call('POST', '/announcements', {
    token: tokens.store_owner,
    body: { title: `Mine ${tag}`, body: 'x', startsOn: today(), endsOn: inAYear(), storeId: fx.storeA },
  });
  assert.equal(ok.status, 201);
  assert.equal(ok.body.announcement.status, 'pending');

  assert.equal((await call('POST', `/announcements/${ok.body.announcement.id}/approve`, { token: tokens.store_owner, body: {} })).status, 403);
  assert.equal((await call('GET', '/owners', { token: tokens.store_owner })).status, 403);
  assert.equal((await call('POST', '/stores', { token: tokens.store_owner, body: { branchId: fx.branchA, name: `Z ${tag}` } })).status, 403);

  const approved = await call('POST', `/announcements/${ok.body.announcement.id}/approve`, { token: tokens.mall_admin, body: {} });
  assert.equal(approved.status, 200);
  assert.equal(approved.body.announcement.status, 'approved');
});

// ---- Superadmin ----

test('superadmin reaches everything', async () => {
  assert.equal((await call('GET', `/malls/${fx.mallB}`, { token: tokens.superadmin })).status, 200);
  assert.equal((await call('GET', '/audit?pageSize=1', { token: tokens.superadmin })).status, 200);
  assert.equal((await call('GET', '/settings', { token: tokens.superadmin })).status, 200);
});
