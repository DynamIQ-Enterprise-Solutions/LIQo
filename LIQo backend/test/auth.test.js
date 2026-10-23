// US-046: sign-in success and failure, forced password change, deactivated accounts.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `t${Date.now().toString(36)}`;
let server;
let call;
let fx;

before(async () => {
  const s = await startServer();
  server = s.server;
  call = api(s.base);
  fx = await makeFixtures(tag);
});

after(async () => {
  await cleanFixtures(tag);
  await stopServer(server);
});

const login = (email, password = PASSWORD) => call('POST', '/auth/login', { body: { email, password } });

test('login succeeds with the right password and returns a token and user', async () => {
  const r = await login(`superadmin.${tag}@test.local`);
  assert.equal(r.status, 200);
  assert.ok(r.body.token);
  assert.equal(r.body.user.role, 'superadmin');
});

test('login fails with a wrong password and never leaks which part was wrong', async () => {
  const r = await login(`superadmin.${tag}@test.local`, 'nope');
  assert.equal(r.status, 401);
  assert.equal(r.body.error, 'Incorrect email or password.');
});

test('login for an unknown email gives the same error', async () => {
  const r = await login(`nobody.${tag}@test.local`);
  assert.equal(r.status, 401);
});

test('failed and successful logins are audited; a failed guess has no actor id', async () => {
  const rows = await db.auditRows({ actorEmail: `superadmin.${tag}@test.local` });
  assert.ok(rows.some((r) => r.action === 'login_success' && r.actor_id === fx.superadminId));
  assert.ok(rows.some((r) => r.action === 'login_failed' && r.actor_id === null));
});

test('a deactivated account cannot sign in', async () => {
  await db.setUser(fx.ownerId, { is_active: false });
  const r = await login(`store_owner.${tag}@test.local`);
  assert.equal(r.status, 403);
  assert.match(r.body.error, /deactivated/i);
  await db.setUser(fx.ownerId, { is_active: true });
});

test('a temporary-password user is blocked until the password is changed', async () => {
  // The fixture user tempUserId was created with must_change_password = 1.
  const temp = (await db.userRow(fx.tempUserId)).email;
  const t = await login(temp);
  assert.equal(t.status, 200);
  assert.equal(t.body.user.mustChangePassword, true);

  const blocked = await call('GET', '/malls', { token: t.body.token });
  assert.equal(blocked.status, 403);
  assert.match(blocked.body.error, /change your password/i);

  const weak = await call('POST', '/auth/change-password', { token: t.body.token, body: { currentPassword: PASSWORD, newPassword: 'short' } });
  assert.equal(weak.status, 400);

  const changed = await call('POST', '/auth/change-password', { token: t.body.token, body: { currentPassword: PASSWORD, newPassword: 'NewPass456' } });
  assert.equal(changed.status, 200);
  assert.equal(changed.body.user.mustChangePassword, false);

  const allowed = await call('GET', '/malls', { token: t.body.token });
  assert.equal(allowed.status, 200);
});

test('requests without a token are refused', async () => {
  const r = await call('GET', '/accounts');
  assert.equal(r.status, 401);
});

test('a garbage token is refused', async () => {
  const r = await call('GET', '/accounts', { token: 'not-a-token' });
  assert.equal(r.status, 401);
});

test('too many wrong passwords lock the account; an admin reset unlocks it', async () => {
  const email = `mall_admin.${tag}@test.local`;
  await db.setSetting('max_login_attempts', 3);
  const { invalidate } = await import('../src/repos/settings.js');
  invalidate();
  try {
    let last;
    for (let i = 0; i < 3; i++) last = await login(email, 'wrong');
    assert.equal(last.status, 423, 'third failure locks');
    const right = await login(email);
    assert.equal(right.status, 423, 'correct password is refused while locked');

    const row = await db.userRow(fx.mallAdminId);
    assert.ok(row.locked_until, 'locked_until is set');

    // An admin reset (new password) clears the lock.
    const admin = await login(`superadmin.${tag}@test.local`);
    const reset = await call('POST', `/accounts/${fx.mallAdminId}/reset-password`, { token: admin.body.token });
    assert.equal(reset.status, 200);
    const after = await login(email, reset.body.tempPassword);
    assert.equal(after.status, 200);
    assert.equal(after.body.user.mustChangePassword, true);
  } finally {
    await db.setSetting('max_login_attempts', 5);
    invalidate();
    await db.setUser(fx.mallAdminId, { failed_logins: 0, locked_until: null });
  }
});

test('a superadmin can create another superadmin, and it is audited as such', async () => {
  const admin = await login(`superadmin.${tag}@test.local`);
  const r = await call('POST', '/accounts', { token: admin.body.token, body: { email: `sa2.${tag}@test.local`, fullName: 'Second Super', role: 'superadmin' } });
  assert.equal(r.status, 201);
  assert.equal(r.body.user.role, 'superadmin');
  const audit = await db.auditRows({ entityType: 'user', entityId: r.body.user.id });
  assert.ok(audit.some((a) => a.action === 'superadmin_created'));
  // The new superadmin can sign in with the temp password and must change it.
  const l = await login(`sa2.${tag}@test.local`, r.body.tempPassword);
  assert.equal(l.status, 200);
  assert.equal(l.body.user.mustChangePassword, true);
});
