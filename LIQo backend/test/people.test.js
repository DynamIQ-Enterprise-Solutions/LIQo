// Round 4: people on a mall, "reports to" links, and what a mall owner may do.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';

const tag = `p${Date.now().toString(36)}`;
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

const login = async (email, password) => (await call('POST', '/auth/login', { body: { email, password } })).body.token;

/** Creates an owner through the API and signs them in with a permanent password. */
async function makeOwner(name, assignments) {
  const r = await call('POST', '/accounts', { token: tokens.superadmin, body: { email: `${name}.${tag}@test.local`, fullName: name, role: 'supervisor', assignments } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  const temp = await login(`${name}.${tag}@test.local`, r.body.tempPassword);
  await call('POST', '/auth/change-password', { token: temp, body: { currentPassword: r.body.tempPassword, newPassword: PASSWORD } });
  return { id: r.body.user.id, token: await login(`${name}.${tag}@test.local`, PASSWORD) };
}

test('people on a mall: whole-mall and branch-level owners, admins with their branches and owner', async () => {
  // A branch-level owner on branch A only.
  const branchOwner = await makeOwner('branchowner', { mallIds: [], branchIds: [fx.branchA] });
  const r = await call('GET', `/malls/${fx.mallA}/people`, { token: tokens.superadmin });
  assert.equal(r.status, 200);
  assert.equal(r.body.mall.id, fx.mallA);
  const whole = r.body.owners.find((o) => o.id === fx.supervisorId);
  assert.equal(whole.wholeMall, true);
  const partial = r.body.owners.find((o) => o.id === branchOwner.id);
  assert.equal(partial.wholeMall, false);
  assert.match(partial.branchNames, /Branch A/);
  const admin = r.body.admins.find((a) => a.id === fx.mallAdminId);
  assert.deepEqual(admin.branches.map((b) => b.id), [fx.branchA]);
  // Round 14 (owner decision 2026-10-22): the branch's own owner comes before the whole-mall owner.
  assert.equal(admin.reportsTo.id, branchOwner.id);

  // Take branch A back from the branch-level owner: the admin returns to the whole-mall owner.
  const freed = await call('PUT', `/assignments/supervisors/${branchOwner.id}`, { token: tokens.superadmin, body: { mallIds: [], branchIds: [] } });
  assert.equal(freed.status, 200);
  const back = await call('GET', `/malls/${fx.mallA}/people`, { token: tokens.superadmin });
  assert.equal(back.body.admins.find((a) => a.id === fx.mallAdminId).reportsTo.id, fx.supervisorId);

  // Round 14 (B12, approved 2026-10-22): an owner may read who runs their mall
  // (owners, and the admins on their own branches); changes stay superadmin-only.
  const asOwner = await call('GET', `/malls/${fx.mallA}/people`, { token: tokens.supervisor });
  assert.equal(asOwner.status, 200);
  assert.ok(asOwner.body.owners.some((o) => o.id === fx.supervisorId));
  const addAsOwner = await call('POST', `/malls/${fx.mallA}/owners`, { token: tokens.supervisor, body: { userId: fx.supervisorId } });
  assert.equal(addAsOwner.status, 403);
  const outside = await call('GET', `/malls/${fx.mallB}/people`, { token: tokens.supervisor });
  assert.equal(outside.status, 403);
});

test('an owner sees only admins that report to them; another owner of the same mall cannot touch them', async () => {
  const other = await makeOwner('otherowner', { mallIds: [fx.mallA], branchIds: [] });
  const mine = await call('GET', '/accounts?pageSize=100', { token: tokens.supervisor });
  assert.ok(mine.body.items.some((u) => u.id === fx.mallAdminId));
  const theirs = await call('GET', '/accounts?pageSize=100', { token: other.token });
  assert.ok(!theirs.body.items.some((u) => u.id === fx.mallAdminId), 'not visible to the other owner');
  const edit = await call('PUT', `/accounts/${fx.mallAdminId}`, { token: other.token, body: { fullName: 'Taken', email: `mall_admin.${tag}@test.local` } });
  assert.equal(edit.status, 403);
  const assign = await call('PUT', `/assignments/mall-admins/${fx.mallAdminId}`, { token: other.token, body: { branchIds: [fx.branchA] } });
  assert.equal(assign.status, 403);
});

// Round 14 (owner decision 2026-10-22): who an admin reports to is no longer
// picked or released by hand; it follows branch ownership. The old manual
// route answers 410 for everyone, and the admin keeps their rule-given owner.
test('reports to cannot be set or released by hand any more', async () => {
  const ownerB = await makeOwner('ownerb', { mallIds: [fx.mallB], branchIds: [] });
  for (const [token, ownerId] of [[tokens.superadmin, ownerB.id], [tokens.supervisor, null]]) {
    const r = await call('PUT', `/accounts/${fx.mallAdminId}/reports-to`, { token, body: { ownerId } });
    assert.equal(r.status, 410);
    assert.match(r.body.error, /set automatically/);
  }
  const still = await call('GET', `/accounts/${fx.mallAdminId}`, { token: tokens.superadmin });
  assert.equal(still.body.user.reportsTo.id, fx.supervisorId);
});

test('an owner creates a mall admin inside their branches; it reports to them and is audited with the owner as actor', async () => {
  const r = await call('POST', '/accounts', {
    token: tokens.supervisor,
    body: { email: `ownermade.${tag}@test.local`, fullName: 'Owner Made', role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchA] } },
  });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.user.reportsTo.id, fx.supervisorId);
  const row = (await db.auditRows({ action: 'account_created', entityId: r.body.user.id }))[0];
  assert.equal(row.actor_id, fx.supervisorId);
  assert.match(row.details, /"createdByRole":"supervisor"/);
  // Visible in the superadmin audit log too.
  const log = await call('GET', `/audit?search=ownermade.${tag}&pageSize=50`, { token: tokens.superadmin });
  assert.equal(log.status, 200);
  assert.ok(log.body.items.some((e) => e.action === 'account_created'));
});

test('from the mall page: add an owner, set an admin branches and owner, remove the owner clears the link', async () => {
  const newOwner = await makeOwner('pageowner', { mallIds: [fx.mallB], branchIds: [] });
  const add = await call('POST', `/malls/${fx.mallA}/owners`, { token: tokens.superadmin, body: { userId: newOwner.id } });
  assert.equal(add.status, 200);
  assert.ok(add.body.owners.some((o) => o.id === newOwner.id && o.wholeMall));

  // A new admin created by the superadmin with no owner, then placed under the new owner from the mall page.
  const admin = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `pageadmin.${tag}@test.local`, fullName: 'Page Admin', role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchA] } },
  });
  // Round 14 (owner decision 2026-10-22): the rule gives the new admin the mall's
  // first-linked whole-mall owner (the fixture owner), not "No owner".
  assert.equal(admin.body.user.reportsTo.id, fx.supervisorId);
  const wrongMall = await call('PUT', `/malls/${fx.mallA}/admins/${admin.body.user.id}`, { token: tokens.superadmin, body: { branchIds: [fx.branchB] } });
  assert.equal(wrongMall.status, 400);
  const manual = await call('PUT', `/malls/${fx.mallA}/admins/${admin.body.user.id}`, { token: tokens.superadmin, body: { branchIds: [fx.branchA], reportsTo: newOwner.id } });
  assert.equal(manual.status, 400, 'reports to is set automatically');
  const set = await call('PUT', `/malls/${fx.mallA}/admins/${admin.body.user.id}`, { token: tokens.superadmin, body: { branchIds: [fx.branchA] } });
  assert.equal(set.status, 200, JSON.stringify(set.body));
  assert.equal(set.body.user.reportsTo.id, fx.supervisorId);

  // Removing the later-linked owner changes nobody's superior.
  const removed = await call('DELETE', `/malls/${fx.mallA}/owners/${newOwner.id}`, { token: tokens.superadmin });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.linksCleared, 0);
  assert.ok(!removed.body.owners.some((o) => o.id === newOwner.id));
  const detail = await call('GET', `/accounts/${admin.body.user.id}`, { token: tokens.superadmin });
  assert.equal(detail.body.user.reportsTo.id, fx.supervisorId);

  // Remove the admin from the mall: branches here are dropped.
  const drop = await call('DELETE', `/malls/${fx.mallA}/admins/${admin.body.user.id}`, { token: tokens.superadmin });
  assert.equal(drop.status, 200);
  assert.equal(drop.body.branches.length, 0);
});
