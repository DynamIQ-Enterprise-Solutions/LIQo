// Round 14: the mall owner dashboard's second gap review (owner decisions 2026-10-22).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `x${Date.now().toString(36)}`;
let server;
let call;
let fx;
const tokens = {};

const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const today = () => ymd(new Date());
const inDays = (n) => ymd(new Date(Date.now() + n * 86400000));

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

test('shared announcement: the owner sees only their part, cannot rewrite it, and removing it leaves the other mall untouched', async () => {
  const post = await call('POST', '/announcements', {
    token: tokens.superadmin,
    body: { title: `Shared ${tag}`, body: 'For both malls', startsOn: today(), endsOn: inDays(7), branchIds: [fx.branchA, fx.branchB] },
  });
  assert.equal(post.status, 201, JSON.stringify(post.body));
  const id = post.body.announcement.id;

  const mine = (await call('GET', `/announcements/${id}`, { token: tokens.supervisor })).body.announcement;
  assert.deepEqual(mine.branches.map((b) => b.id), [fx.branchA], 'only their own branch is listed');
  assert.equal(mine.sharedBeyondScope, true);
  assert.equal(mine.canChange, false);
  assert.equal(mine.canDetach, true);

  const edit = await call('PUT', `/announcements/${id}`, { token: tokens.supervisor, body: { title: 'Rewritten', body: 'x', startsOn: today(), endsOn: inDays(7) } });
  assert.equal(edit.status, 403);

  const removed = await call('DELETE', `/announcements/${id}`, { token: tokens.supervisor });
  assert.equal(removed.status, 200);
  assert.deepEqual(removed.body.detached, [fx.branchA]);

  const left = (await call('GET', `/announcements/${id}`, { token: tokens.superadmin })).body.announcement;
  assert.deepEqual(left.branches.map((b) => b.id), [fx.branchB], 'the other mall keeps it');
  assert.equal((await call('GET', `/announcements/${id}`, { token: tokens.supervisor })).status, 403, 'gone for the owner');

  const author = await call('PUT', `/announcements/${id}`, { token: tokens.superadmin, body: { title: `Shared ${tag} v2`, body: 'x', startsOn: today(), endsOn: inDays(7) } });
  assert.equal(author.status, 200, 'its author can still change it');
});

test("an owner's own announcement inside their scope is fully theirs; store-owner submissions are read-only for them", async () => {
  const own = await call('POST', '/announcements', { token: tokens.supervisor, body: { title: `Own ${tag}`, body: 'x', startsOn: today(), endsOn: inDays(3), branchIds: [fx.branchA] } });
  assert.equal(own.status, 201);
  assert.equal(own.body.announcement.canChange, true);
  assert.equal((await call('DELETE', `/announcements/${own.body.announcement.id}`, { token: tokens.supervisor })).status, 204);

  const sub = await call('POST', '/announcements', { token: tokens.store_owner, body: { title: `Sub ${tag}`, body: 'x', startsOn: today(), endsOn: inDays(3), storeId: fx.storeA } });
  assert.equal(sub.status, 201);
  const id = sub.body.announcement.id;
  assert.equal((await call('GET', `/announcements/${id}`, { token: tokens.supervisor })).body.announcement.canChange, false);
  assert.equal((await call('PUT', `/announcements/${id}`, { token: tokens.supervisor, body: { title: 'x', body: 'x', startsOn: today(), endsOn: inDays(3) } })).status, 403);
  assert.equal((await call('DELETE', `/announcements/${id}`, { token: tokens.supervisor })).status, 403);
});

test('announcement checks: already over, or an image that is not a web link, is refused', async () => {
  const late = await call('POST', '/announcements', { token: tokens.supervisor, body: { title: `Late ${tag}`, body: 'x', startsOn: inDays(-5), endsOn: inDays(-1), branchIds: [fx.branchA] } });
  assert.equal(late.status, 400);
  const img = await call('POST', '/announcements', { token: tokens.supervisor, body: { title: `Img ${tag}`, body: 'x', startsOn: today(), endsOn: inDays(1), branchIds: [fx.branchA], imageUrl: 'not a link' } });
  assert.equal(img.status, 400);
});

test('an inactive branch: its owner still reads its stores and map; its mall admin does not', async () => {
  const map = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { width: 30, depth: 20 } });
  assert.equal(map.status, 201);
  const off = await call('POST', `/branches/${fx.branchA}/deactivate`, { token: tokens.supervisor });
  assert.equal(off.status, 200);
  try {
    const stores = await call('GET', `/stores?branchId=${fx.branchA}&pageSize=50`, { token: tokens.supervisor });
    assert.ok(stores.body.items.some((s) => s.id === fx.storeA));
    assert.equal((await call('GET', `/stores/${fx.storeA}`, { token: tokens.supervisor })).status, 200);
    const list = await call('GET', '/maps', { token: tokens.supervisor });
    const row = list.body.items.find((m) => m.branchId === fx.branchA);
    assert.ok(row && row.branchActive === false);
    assert.equal((await call('GET', `/maps/${fx.branchA}`, { token: tokens.supervisor })).status, 200);
    assert.equal((await call('GET', `/stores/${fx.storeA}`, { token: tokens.mall_admin })).status, 403);
  } finally {
    await call('POST', `/branches/${fx.branchA}/reactivate`, { token: tokens.supervisor });
  }
});

test('the owner gets the published map only: no draft, lock, versions or checks', async () => {
  const bundle = (await call('GET', `/maps/${fx.branchA}`, { token: tokens.supervisor })).body;
  assert.equal(bundle.canEdit, false);
  assert.ok(bundle.map);
  assert.equal(bundle.map.draft, undefined);
  assert.equal(bundle.map.lock, undefined);
  assert.deepEqual(bundle.versions, []);
  assert.deepEqual(bundle.warnings, []);
  const admin = (await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin })).body;
  assert.ok(admin.map.draft, 'the mall admin still gets the draft');
});

test('"Active" counts leave out deactivated stores and accounts', async () => {
  const before = (await call('GET', '/analytics/overview', { token: tokens.supervisor })).body.counts;
  const off = await call('POST', `/stores/${fx.storeA}/deactivate`, { token: tokens.mall_admin });
  assert.equal(off.status, 200, JSON.stringify(off.body));
  await db.setUser(fx.ownerId, { is_active: false });
  try {
    const after = (await call('GET', '/analytics/overview', { token: tokens.supervisor })).body.counts;
    assert.equal(after.stores, before.stores - 1);
    assert.equal(after.accounts, before.accounts - 1);
  } finally {
    await call('POST', `/stores/${fx.storeA}/reactivate`, { token: tokens.mall_admin });
    await db.setUser(fx.ownerId, { is_active: true });
  }
});

test("an owner of one branch sees that mall's branch count as their branches only", async () => {
  const extra = await call('POST', '/branches', { token: tokens.superadmin, body: { mallId: fx.mallA, name: `Branch A2 ${tag}` } });
  assert.equal(extra.status, 201, JSON.stringify(extra.body));
  const email = `onebranch.${tag}@test.local`;
  const r = await call('POST', '/accounts', { token: tokens.superadmin, body: { email, fullName: 'One Branch', role: 'supervisor', assignments: { mallIds: [], branchIds: [fx.branchA] } } });
  const temp = (await call('POST', '/auth/login', { body: { email, password: r.body.tempPassword } })).body.token;
  await call('POST', '/auth/change-password', { token: temp, body: { currentPassword: r.body.tempPassword, newPassword: PASSWORD } });
  const token = (await call('POST', '/auth/login', { body: { email, password: PASSWORD } })).body.token;
  assert.equal((await call('GET', `/malls/${fx.mallA}`, { token })).body.mall.branchCount, 1);
  assert.equal((await call('GET', `/malls/${fx.mallA}`, { token: tokens.superadmin })).body.mall.branchCount, 2);
  // Free branch A again so the fixture admin reports to the whole-mall owner for later tests.
  await call('PUT', `/assignments/supervisors/${r.body.user.id}`, { token: tokens.superadmin, body: { mallIds: [], branchIds: [] } });
});

test("editing an admin directly respects emails waiting in requests and cancels the admin's own request", async () => {
  const wanted = `wanted.${tag}@test.local`;
  const other = await call('POST', '/profile/request', { token: tokens.store_owner, body: { fullName: `store_owner ${tag}`, email: wanted } });
  assert.equal(other.status, 201, JSON.stringify(other.body));
  const taken = await call('PUT', `/accounts/${fx.mallAdminId}`, { token: tokens.supervisor, body: { fullName: `mall_admin ${tag}`, email: wanted } });
  assert.equal(taken.status, 409);
  await call('DELETE', '/profile/request', { token: tokens.store_owner });

  const own = await call('POST', '/profile/request', { token: tokens.mall_admin, body: { fullName: 'Their Own Choice', email: `mall_admin.${tag}@test.local` } });
  assert.equal(own.status, 201);
  const edit = await call('PUT', `/accounts/${fx.mallAdminId}`, { token: tokens.supervisor, body: { fullName: 'Set By Owner', email: `mall_admin.${tag}@test.local` } });
  assert.equal(edit.status, 200);
  const req = (await call('GET', '/profile/request', { token: tokens.mall_admin })).body.request;
  assert.equal(req.status, 'cancelled');
});

test('a branch save keeps the fields it did not send, and a logo must be a web link', async () => {
  const full = await call('PUT', `/branches/${fx.branchA}`, { token: tokens.supervisor, body: { address: '1 Bay Blvd', openingHours: '10:00-21:00', contactPhone: '123' } });
  assert.equal(full.status, 200);
  const partial = await call('PUT', `/branches/${fx.branchA}`, { token: tokens.supervisor, body: { openingHours: '09:00-22:00' } });
  assert.equal(partial.body.branch.openingHours, '09:00-22:00');
  assert.equal(partial.body.branch.address, '1 Bay Blvd');
  assert.equal(partial.body.branch.contactPhone, '123');
  const logo = await call('PUT', `/branches/${fx.branchA}`, { token: tokens.supervisor, body: { logoUrl: 'logo.png' } });
  assert.equal(logo.status, 400);
});

test('My account: what each person has access to', async () => {
  const owner = (await call('GET', '/profile/access', { token: tokens.supervisor })).body;
  assert.ok(owner.malls.some((m) => m.id === fx.mallA));
  const admin = (await call('GET', '/profile/access', { token: tokens.mall_admin })).body;
  assert.deepEqual(admin.branches.map((b) => b.id), [fx.branchA]);
  assert.equal(admin.reportsTo.id, fx.supervisorId);
  const so = (await call('GET', '/profile/access', { token: tokens.store_owner })).body;
  assert.ok(so.stores.some((s) => s.id === fx.storeA));
});
