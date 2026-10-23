// Round 8: people change their own name and email. A superadmin's change
// applies at once; everyone else sends a request a superadmin decides.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `r${Date.now().toString(36)}`;
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

const actions = async (userId) => (await db.auditRows({ entityType: 'user', entityId: userId })).map((a) => a.action);

test("a superadmin changes their own details at once; a taken email is refused", async () => {
  const ok = await call('PUT', '/profile', { token: tokens.superadmin, body: { fullName: `Super Renamed ${tag}`, email: `superadmin.${tag}@test.local` } });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal(ok.body.user.fullName, `Super Renamed ${tag}`);
  assert.ok((await actions(fx.superadminId)).includes('profile_updated'));

  const taken = await call('PUT', '/profile', { token: tokens.superadmin, body: { fullName: 'X Y', email: `mall_admin.${tag}@test.local` } });
  assert.equal(taken.status, 409);
});

test('a mall admin cannot change details directly; a request waits, one at a time, and can be cancelled', async () => {
  const direct = await call('PUT', '/profile', { token: tokens.mall_admin, body: { fullName: 'Direct', email: `mall_admin.${tag}@test.local` } });
  assert.equal(direct.status, 403);

  const same = await call('POST', '/profile/request', { token: tokens.mall_admin, body: { fullName: `mall_admin ${tag}`, email: `mall_admin.${tag}@test.local` } });
  assert.equal(same.status, 400, 'nothing changed');

  const sent = await call('POST', '/profile/request', { token: tokens.mall_admin, body: { fullName: 'Mall Admin Renamed', email: `ma.new.${tag}@test.local` } });
  assert.equal(sent.status, 201, JSON.stringify(sent.body));
  assert.equal(sent.body.request.status, 'pending');
  assert.equal(sent.body.request.current.email, `mall_admin.${tag}@test.local`, 'nothing changes until approval');

  const second = await call('POST', '/profile/request', { token: tokens.mall_admin, body: { fullName: 'Again', email: `ma.again.${tag}@test.local` } });
  assert.equal(second.status, 409);

  const cancel = await call('DELETE', '/profile/request', { token: tokens.mall_admin });
  assert.equal(cancel.status, 200);
  assert.equal(cancel.body.request.status, 'cancelled');
  assert.equal((await call('DELETE', '/profile/request', { token: tokens.mall_admin })).status, 404);
  assert.ok((await actions(fx.mallAdminId)).includes('profile_change_cancelled'));
});

test('a superadmin approves: name and email change, the old password signs in with the new email', async () => {
  const sent = await call('POST', '/profile/request', { token: tokens.mall_admin, body: { fullName: 'Mall Admin Approved', email: `ma.approved.${tag}@test.local` } });
  assert.equal(sent.status, 201);

  const list = await call('GET', '/profile-requests', { token: tokens.superadmin });
  assert.ok(list.body.items.some((r) => r.id === sent.body.request.id));
  assert.equal((await call('GET', '/profile-requests', { token: tokens.mall_admin })).status, 403);
  assert.equal((await call('GET', '/profile-requests', { token: tokens.supervisor })).status, 403);

  const approved = await call('POST', `/profile-requests/${sent.body.request.id}/approve`, { token: tokens.superadmin });
  assert.equal(approved.status, 200, JSON.stringify(approved.body));
  assert.equal(approved.body.request.status, 'approved');
  assert.equal(approved.body.request.current.email, `ma.approved.${tag}@test.local`);

  const signIn = await call('POST', '/auth/login', { body: { email: `ma.approved.${tag}@test.local`, password: PASSWORD } });
  assert.equal(signIn.status, 200);
  assert.equal(signIn.body.user.fullName, 'Mall Admin Approved');
  assert.equal((await call('POST', `/profile-requests/${sent.body.request.id}/approve`, { token: tokens.superadmin })).status, 409, 'already decided');
  assert.ok((await actions(fx.mallAdminId)).includes('profile_change_approved'));
});

test('a rejection needs a reason, which the person then sees', async () => {
  const sent = await call('POST', '/profile/request', { token: tokens.store_owner, body: { fullName: 'Owner Renamed', email: `store_owner.${tag}@test.local` } });
  assert.equal(sent.status, 201);
  const noReason = await call('POST', `/profile-requests/${sent.body.request.id}/reject`, { token: tokens.superadmin, body: {} });
  assert.equal(noReason.status, 400);
  const rejected = await call('POST', `/profile-requests/${sent.body.request.id}/reject`, { token: tokens.superadmin, body: { reason: 'Use your legal name.' } });
  assert.equal(rejected.status, 200);
  const mine = await call('GET', '/profile/request', { token: tokens.store_owner });
  assert.equal(mine.body.request.status, 'rejected');
  assert.equal(mine.body.request.reason, 'Use your legal name.');
});

test('an email taken between request and approval blocks the approval and keeps the request waiting', async () => {
  const wanted = `wanted.${tag}@test.local`;
  const sent = await call('POST', '/profile/request', { token: tokens.supervisor, body: { fullName: `supervisor ${tag}`, email: wanted } });
  assert.equal(sent.status, 201);
  // Someone else takes the email first (superadmin changes their own email to it).
  const grab = await call('PUT', '/profile', { token: tokens.superadmin, body: { fullName: `Super Renamed ${tag}`, email: wanted } });
  assert.equal(grab.status, 409, 'the waiting request already reserves it');
  // Force the clash through the database to test the approval-time check.
  await db.setUser(fx.ownerId, { email: wanted });
  const approve = await call('POST', `/profile-requests/${sent.body.request.id}/approve`, { token: tokens.superadmin });
  assert.equal(approve.status, 409);
  const still = await call('GET', `/profile-requests/${sent.body.request.id}`, { token: tokens.superadmin });
  assert.equal(still.body.request.status, 'pending');
  await db.setUser(fx.ownerId, { email: `store_owner.${tag}@test.local` });
});
