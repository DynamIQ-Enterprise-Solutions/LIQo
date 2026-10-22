// The create wizards' live checks (owner decisions 2026-10-22): one account per
// email, who-holds-it only for a superadmin, a warning for an email waiting in a
// profile change request, a warning for a repeated name, the admins already on
// a branch, and store-owner emails (active: the store is added; inactive: blocked).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import { query, sql } from '../src/db/pool.js';

const tag = `w${Date.now().toString(36)}`;
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

const check = (role, params) => call('GET', `/accounts/check?${new URLSearchParams(params)}`, { token: tokens[role] });
const setActive = (id, on) => query(`UPDATE users SET is_active = @a WHERE id = @id`, { a: { type: sql.Bit, value: on ? 1 : 0 }, id: { type: sql.Int, value: id } });

test('email: free, taken and inactive; only a superadmin learns who holds it', async () => {
  const free = await check('superadmin', { email: `nobody.${tag}@test.local` });
  assert.equal(free.status, 200);
  assert.equal(free.body.email.state, 'free');

  const taken = await check('superadmin', { email: `Mall_Admin.${tag}@test.local` });
  assert.equal(taken.body.email.state, 'taken', 'letter case does not matter');
  assert.equal(taken.body.email.account.id, fx.mallAdminId);
  assert.equal(taken.body.email.account.role, 'mall_admin');

  const owner = await check('supervisor', { email: `mall_admin.${tag}@test.local` });
  assert.equal(owner.body.email.state, 'taken');
  assert.equal(owner.body.email.account, undefined, 'a mall owner sees no details');

  await setActive(fx.mallAdminId, false);
  try {
    const inactive = await check('superadmin', { email: `mall_admin.${tag}@test.local` });
    assert.equal(inactive.body.email.state, 'inactive');
    assert.equal(inactive.body.email.account.isActive, false);
    const create = await call('POST', '/accounts', { token: tokens.superadmin, body: { email: `mall_admin.${tag}@test.local`, fullName: 'Copy', role: 'supervisor', assignments: { mallIds: [fx.mallA], branchIds: [] } } });
    assert.equal(create.status, 409);
    assert.match(create.body.error, /inactive/);
  } finally {
    await setActive(fx.mallAdminId, true);
  }

  const bad = await check('superadmin', { email: 'not-an-email' });
  assert.equal(bad.body.email.state, 'invalid');
});

test('an email waiting in a profile change request warns but does not block', async () => {
  const wanted = `wanted.${tag}@test.local`;
  const req = await call('POST', '/profile/request', { token: tokens.mall_admin, body: { fullName: `mall_admin ${tag}`, email: wanted } });
  assert.equal(req.status, 201, JSON.stringify(req.body));

  const r = await check('superadmin', { email: wanted });
  assert.equal(r.body.email.state, 'pending_request');

  const create = await call('POST', '/accounts', { token: tokens.superadmin, body: { email: wanted, fullName: 'Takes It', role: 'supervisor', assignments: { mallIds: [fx.mallA], branchIds: [] } } });
  assert.equal(create.status, 201, 'allowed, as decided');
  await call('DELETE', '/profile/request', { token: tokens.mall_admin });
});

test('a repeated full name is counted; only a superadmin sees who', async () => {
  const sup = await check('superadmin', { fullName: `  MALL_ADMIN ${tag} ` });
  assert.equal(sup.body.name.count, 1);
  assert.equal(sup.body.name.matches[0].role, 'mall_admin');

  const owner = await check('supervisor', { fullName: `mall_admin ${tag}` });
  assert.equal(owner.body.name.count, 1);
  assert.equal(owner.body.name.matches, undefined);

  const none = await check('superadmin', { fullName: `Nobody ${tag}` });
  assert.equal(none.body.name.count, 0);
});

test('branch admins: listed for a superadmin and an owner in scope; out of scope is refused', async () => {
  const sup = await check('superadmin', { branchId: fx.branchA });
  assert.deepEqual(sup.body.branchAdmins.map((a) => a.id), [fx.mallAdminId]);

  const owner = await check('supervisor', { branchId: fx.branchA });
  assert.equal(owner.body.branchAdmins.length, 1);

  const outside = await check('supervisor', { branchId: fx.branchB });
  assert.equal(outside.status, 403);

  const admin = await check('mall_admin', { branchId: fx.branchA });
  assert.equal(admin.body.branchAdmins, undefined);
});

test('store-owner emails: an active owner gets the store added, an inactive one is blocked', async () => {
  const email = `store_owner.${tag}@test.local`;
  const active = await check('mall_admin', { email, purpose: 'store_owner' });
  assert.equal(active.body.email.state, 'store_owner');
  assert.equal(active.body.email.account.id, fx.ownerId);
  assert.equal(active.body.email.canOpen, true);

  const otherRole = await check('mall_admin', { email: `supervisor.${tag}@test.local`, purpose: 'store_owner' });
  assert.equal(otherRole.body.email.state, 'taken');
  assert.equal(otherRole.body.email.account, undefined);

  await setActive(fx.ownerId, false);
  try {
    const inactive = await check('mall_admin', { email, purpose: 'store_owner' });
    assert.equal(inactive.body.email.state, 'inactive');
    const add = await call('POST', '/owners', { token: tokens.mall_admin, body: { email, fullName: 'Whoever', storeId: fx.storeA } });
    assert.equal(add.status, 409);
    assert.match(add.body.error, /inactive/i);
  } finally {
    await setActive(fx.ownerId, true);
  }
});

test('store owners cannot use the checks', async () => {
  const r = await check('store_owner', { email: `x.${tag}@test.local` });
  assert.equal(r.status, 403);
});
