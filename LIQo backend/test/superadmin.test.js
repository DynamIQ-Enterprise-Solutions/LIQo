// Round 8: a superadmin manages another superadmin (with safeguards) and can
// clear a stuck map edit lock.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `s${Date.now().toString(36)}`;
let server;
let call;
let fx;
const tokens = {};

before(async () => {
  const s = await startServer();
  server = s.server;
  call = api(s.base);
  fx = await makeFixtures(tag);
  for (const role of ['superadmin', 'supervisor', 'mall_admin']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
});

after(async () => {
  await cleanFixtures(tag);
  await stopServer(server);
});

const login = (email, password) => call('POST', '/auth/login', { body: { email, password } });

/** A second superadmin, created through the API and past its temporary password. */
async function secondSuperadmin(name) {
  const email = `${name}.${tag}@test.local`;
  const r = await call('POST', '/accounts', { token: tokens.superadmin, body: { email, fullName: name, role: 'superadmin' } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  const temp = (await login(email, r.body.tempPassword)).body.token;
  await call('POST', '/auth/change-password', { token: temp, body: { currentPassword: r.body.tempPassword, newPassword: PASSWORD } });
  return { id: r.body.user.id, email };
}

const auditActions = async (entityId) =>
  (await db.auditRows({ entityId })).map((a) => a.action);

test('a superadmin opens, deactivates and reactivates another superadmin; it is audited and sign-in follows', async () => {
  const b = await secondSuperadmin('saB');
  const view = await call('GET', `/accounts/${b.id}`, { token: tokens.superadmin });
  assert.equal(view.status, 200);
  assert.equal(view.body.user.role, 'superadmin');

  const off = await call('POST', `/accounts/${b.id}/deactivate`, { token: tokens.superadmin });
  assert.equal(off.status, 200, JSON.stringify(off.body));
  assert.equal(off.body.user.isActive, false);
  assert.equal((await login(b.email, PASSWORD)).status, 403);

  const on = await call('POST', `/accounts/${b.id}/reactivate`, { token: tokens.superadmin });
  assert.equal(on.status, 200);
  assert.equal((await login(b.email, PASSWORD)).status, 200);

  const actions = await auditActions(b.id);
  assert.ok(actions.includes('superadmin_deactivated'));
  assert.ok(actions.includes('superadmin_reactivated'));
});

test("a superadmin resets another superadmin's password but cannot edit their name or email", async () => {
  const b = await secondSuperadmin('saC');
  const reset = await call('POST', `/accounts/${b.id}/reset-password`, { token: tokens.superadmin });
  assert.equal(reset.status, 200);
  const signIn = await login(b.email, reset.body.tempPassword);
  assert.equal(signIn.status, 200);
  assert.equal(signIn.body.user.mustChangePassword, true);
  assert.ok((await auditActions(b.id)).includes('superadmin_password_reset'));

  const edit = await call('PUT', `/accounts/${b.id}`, { token: tokens.superadmin, body: { fullName: 'Renamed', email: b.email } });
  assert.equal(edit.status, 403);
});

test('a superadmin still cannot deactivate their own account', async () => {
  const self = await call('POST', `/accounts/${fx.superadminId}/deactivate`, { token: tokens.superadmin });
  assert.equal(self.status, 400);
});

test('only the superadmin can clear a map edit lock; it is audited with the previous holder', async () => {
  const created = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { width: 20, depth: 20 } });
  assert.equal(created.status, 201);
  const lock = await call('POST', `/maps/${fx.branchA}/lock`, { token: tokens.mall_admin });
  assert.equal(lock.status, 200);

  assert.equal((await call('POST', `/maps/${fx.branchA}/lock/force-release`, { token: tokens.mall_admin })).status, 403);
  assert.equal((await call('POST', `/maps/${fx.branchA}/lock/force-release`, { token: tokens.supervisor })).status, 403);

  const released = await call('POST', `/maps/${fx.branchA}/lock/force-release`, { token: tokens.superadmin });
  assert.equal(released.status, 200, JSON.stringify(released.body));
  assert.equal(released.body.released, true);
  assert.equal(released.body.previousHolder, `mall_admin ${tag}`);

  const map = await call('GET', `/maps/${fx.branchA}`, { token: tokens.superadmin });
  assert.equal(map.body.map.lock, null, 'the lock is gone');
  const audit = await db.auditRows({ action: 'map_lock_force_released', entityId: created.body.map?.id ?? map.body.map.id });
  assert.equal(audit.length, 1);
  assert.match(audit[0].details, /previousHolder/);

  const none = await call('POST', `/maps/${fx.branchB}/lock/force-release`, { token: tokens.superadmin });
  assert.equal(none.status, 404, 'a branch without a map');
});
