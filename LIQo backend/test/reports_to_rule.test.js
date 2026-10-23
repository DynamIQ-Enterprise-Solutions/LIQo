// Round 14 (owner decisions 2026-10-22): a mall admin's superior follows branch
// ownership: the owner of their branch first, else the mall's whole-mall owner,
// the one linked first; inactive owners are skipped; nobody → "No owner".
// Recomputed after every change.
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
  for (const role of ['superadmin', 'supervisor']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
});

after(async () => {
  await cleanFixtures(tag);
  await stopServer(server);
});

async function makeOwner(name, assignments) {
  const r = await call('POST', '/accounts', { token: tokens.superadmin, body: { email: `${name}.${tag}@test.local`, fullName: name, role: 'supervisor', assignments } });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  return r.body.user.id;
}

const superiorOf = async (id) => (await call('GET', `/accounts/${id}`, { token: tokens.superadmin })).body.user.reportsTo?.id ?? null;

test('the first-linked whole-mall owner keeps the admin; a branch-level owner takes them over', async () => {
  assert.equal(await superiorOf(fx.mallAdminId), fx.supervisorId, 'the fixture owner owns mall A');

  await makeOwner('second', { mallIds: [fx.mallA], branchIds: [] });
  assert.equal(await superiorOf(fx.mallAdminId), fx.supervisorId, 'a later whole-mall owner does not take over');

  const branchOwner = await makeOwner('branchboss', { mallIds: [], branchIds: [fx.branchA] });
  assert.equal(await superiorOf(fx.mallAdminId), branchOwner, 'the branch\'s own owner comes first');

  const audit = await db.auditRows({ action: 'reports_to_recomputed', detailsContains: String(fx.mallAdminId) });
  assert.ok(audit.length > 0, 'the change is audited');
});

test('an inactive owner is skipped, and their admins come back when they are reactivated', async () => {
  const branchOwner = await db.userIdByEmail(`branchboss.${tag}@test.local`);
  const off = await call('POST', `/accounts/${branchOwner}/deactivate`, { token: tokens.superadmin });
  assert.equal(off.status, 200);
  assert.equal(await superiorOf(fx.mallAdminId), fx.supervisorId);

  const on = await call('POST', `/accounts/${branchOwner}/reactivate`, { token: tokens.superadmin });
  assert.equal(on.status, 200);
  assert.equal(await superiorOf(fx.mallAdminId), branchOwner);

  // Hand branch A back so the next test starts from the whole-mall owner.
  await call('PUT', `/assignments/supervisors/${branchOwner}`, { token: tokens.superadmin, body: { mallIds: [], branchIds: [] } });
  assert.equal(await superiorOf(fx.mallAdminId), fx.supervisorId);
});

test('moving an admin moves their superior; a branch nobody owns means "No owner"; the old owner loses them', async () => {
  // Mall B has no owner.
  const moved = await call('PUT', `/assignments/mall-admins/${fx.mallAdminId}`, { token: tokens.superadmin, body: { branchIds: [fx.branchB] } });
  assert.equal(moved.status, 200);
  assert.equal(moved.body.user.reportsTo, null);
  const noOwner = await call('GET', '/accounts?status=no_owner&pageSize=200', { token: tokens.superadmin });
  assert.ok(noOwner.body.items.some((u) => u.id === fx.mallAdminId));

  // The former owner can no longer see or change them.
  assert.equal((await call('GET', `/accounts/${fx.mallAdminId}`, { token: tokens.supervisor })).status, 403);
  assert.equal((await call('PUT', `/accounts/${fx.mallAdminId}`, { token: tokens.supervisor, body: { fullName: 'Nope', email: `mall_admin.${tag}@test.local` } })).status, 403);

  // An owner linked to mall B later picks them up automatically.
  const ownerB = await makeOwner('ownerb', { mallIds: [fx.mallB], branchIds: [] });
  assert.equal(await superiorOf(fx.mallAdminId), ownerB);

  // Back to branch A: back under the fixture owner.
  const back = await call('PUT', `/assignments/mall-admins/${fx.mallAdminId}`, { token: tokens.superadmin, body: { branchIds: [fx.branchA] } });
  assert.equal(back.body.user.reportsTo.id, fx.supervisorId);
});

test('removing an owner from a mall hands their admins to the next owner by the rule', async () => {
  const second = await db.userIdByEmail(`second.${tag}@test.local`);
  const removed = await call('DELETE', `/malls/${fx.mallA}/owners/${fx.supervisorId}`, { token: tokens.superadmin });
  assert.equal(removed.status, 200);
  assert.equal(removed.body.linksCleared, 1);
  assert.equal(await superiorOf(fx.mallAdminId), second, 'the next whole-mall owner takes over');
  // Restore the fixture owner (now linked after "second", who keeps the admin).
  await call('POST', `/malls/${fx.mallA}/owners`, { token: tokens.superadmin, body: { userId: fx.supervisorId } });
  assert.equal(await superiorOf(fx.mallAdminId), second);
});
