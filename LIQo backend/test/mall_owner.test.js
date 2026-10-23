// Round 9: the mall owner dashboard. Whole-mall ownership for mall changes,
// owners keep seeing what they deactivated, team activity, and announcement
// review by mall admins only.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `o${Date.now().toString(36)}`;
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

/** An owner of one branch only, signed in. */
async function branchLevelOwner() {
  const email = `branchowner.${tag}@test.local`;
  const r = await call('POST', '/accounts', { token: tokens.superadmin, body: { email, fullName: 'Branch Owner', role: 'supervisor', assignments: { mallIds: [], branchIds: [fx.branchA] } } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  const temp = (await call('POST', '/auth/login', { body: { email, password: r.body.tempPassword } })).body.token;
  await call('POST', '/auth/change-password', { token: temp, body: { currentPassword: r.body.tempPassword, newPassword: PASSWORD } });
  return (await call('POST', '/auth/login', { body: { email, password: PASSWORD } })).body.token;
}

test('an owner of one branch sees the mall but cannot rename, deactivate or reactivate it', async () => {
  const token = await branchLevelOwner();
  const view = await call('GET', `/malls/${fx.mallA}`, { token });
  assert.equal(view.status, 200);
  assert.equal(view.body.canManage, false);
  assert.equal((await call('PUT', `/malls/${fx.mallA}`, { token, body: { name: `Hijacked ${tag}` } })).status, 403);
  assert.equal((await call('POST', `/malls/${fx.mallA}/deactivate`, { token })).status, 403);
  assert.equal((await call('POST', `/malls/${fx.mallA}/reactivate`, { token })).status, 403);

  const whole = await call('GET', `/malls/${fx.mallA}`, { token: tokens.supervisor });
  assert.equal(whole.body.canManage, true, 'the fixture owner owns the whole mall');
  const superadmin = await call('GET', `/malls/${fx.mallA}`, { token: tokens.superadmin });
  assert.equal(superadmin.body.canManage, true);
});

test('an owner who deactivates their mall still sees it, marked inactive, and can reactivate it', async () => {
  const off = await call('POST', `/malls/${fx.mallA}/deactivate`, { token: tokens.supervisor });
  assert.equal(off.status, 200);
  try {
    const list = await call('GET', '/malls?pageSize=100', { token: tokens.supervisor });
    const row = list.body.items.find((m) => m.id === fx.mallA);
    assert.ok(row, 'still listed');
    assert.equal(row.isActive, false);
    assert.equal((await call('GET', `/malls/${fx.mallA}`, { token: tokens.supervisor })).status, 200);
    // Everything else stays hidden: the mall admin of its branch loses access as before.
    assert.equal((await call('GET', `/branches/${fx.branchA}`, { token: tokens.mall_admin })).status, 403);
  } finally {
    const on = await call('POST', `/malls/${fx.mallA}/reactivate`, { token: tokens.supervisor });
    assert.equal(on.status, 200);
  }
});

test('an owner who deactivates a branch still sees it and can reactivate it', async () => {
  const off = await call('POST', `/branches/${fx.branchA}/deactivate`, { token: tokens.supervisor });
  assert.equal(off.status, 200);
  try {
    const list = await call('GET', '/branches?pageSize=100', { token: tokens.supervisor });
    const row = list.body.items.find((b) => b.id === fx.branchA);
    assert.ok(row, 'still listed');
    assert.equal(row.isActive, false);
    assert.equal((await call('GET', `/branches/${fx.branchA}`, { token: tokens.supervisor })).status, 200);
  } finally {
    const on = await call('POST', `/branches/${fx.branchA}/reactivate`, { token: tokens.supervisor });
    assert.equal(on.status, 200);
  }
});

test("an owner's recent activity includes what their mall admins did", async () => {
  // Round 14 (owner decision 2026-10-22: "reports to" follows branch ownership,
  // branch-level owner first): an earlier test here made a branch-level owner of
  // branch A, so the fixture admin now reports to them. Take that branch back so
  // the admin reports to the whole-mall owner again, as this test needs.
  const boId = await db.userIdByEmail(`branchowner.${tag}@test.local`);
  const bo = boId ? { id: boId } : undefined;
  if (bo) {
    const freed = await call('PUT', `/assignments/supervisors/${bo.id}`, { token: tokens.superadmin, body: { mallIds: [], branchIds: [] } });
    assert.equal(freed.status, 200);
  }
  const store = await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `Team Store ${tag}` } });
  assert.equal(store.status, 201);
  const overview = await call('GET', '/analytics/overview', { token: tokens.supervisor });
  assert.ok(overview.body.recent.some((a) => a.actorEmail === `mall_admin.${tag}@test.local`), 'the admin who reports to the owner shows up');
  const mine = await call('GET', '/analytics/overview', { token: tokens.mall_admin });
  assert.ok(mine.body.recent.every((a) => a.actorEmail === `mall_admin.${tag}@test.local`), 'a mall admin still sees only their own actions');
});

test('store-owner announcements are reviewed by mall admins; owners can no longer approve or reject', async () => {
  const today = new Date().toISOString().slice(0, 10);
  const sub = await call('POST', '/announcements', { token: tokens.store_owner, body: { title: `Review ${tag}`, body: 'x', startsOn: today, endsOn: today, storeId: fx.storeA } });
  assert.equal(sub.status, 201);
  const id = sub.body.announcement.id;
  assert.equal((await call('POST', `/announcements/${id}/approve`, { token: tokens.supervisor, body: {} })).status, 403);
  assert.equal((await call('POST', `/announcements/${id}/reject`, { token: tokens.supervisor, body: { reason: 'no' } })).status, 403);
  const seen = await call('GET', `/announcements/${id}`, { token: tokens.supervisor });
  assert.equal(seen.status, 200, 'owners still see pending submissions in their scope');
  assert.equal((await call('POST', `/announcements/${id}/approve`, { token: tokens.mall_admin, body: {} })).status, 200);
});
