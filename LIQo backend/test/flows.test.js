// Business flows that cross more than one role: announcement review, store owner
// lifecycle, option-list protection, map lock and stale saves, assignments at
// account creation, effective-active cascade, session timeout from settings.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import * as db from './support/testDb.js';
import * as settings from '../src/repos/settings.js';

const tag = `f${Date.now().toString(36)}`;
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

test('store owner submission must be reviewed by a mall admin; rejection needs a reason', async () => {
  const sub = await call('POST', '/announcements', {
    token: tokens.store_owner,
    body: { title: `Sale ${tag}`, body: 'x', startsOn: today, endsOn: today, storeId: fx.storeA },
  });
  assert.equal(sub.status, 201);
  assert.equal(sub.body.announcement.status, 'pending');
  const id = sub.body.announcement.id;

  // Not visible as live to anyone yet.
  const liveBefore = await call('GET', '/announcements?live=live&pageSize=100', { token: tokens.mall_admin });
  assert.ok(!liveBefore.body.items.some((a) => a.id === id));

  const noReason = await call('POST', `/announcements/${id}/reject`, { token: tokens.mall_admin, body: {} });
  assert.equal(noReason.status, 400);

  const ok = await call('POST', `/announcements/${id}/approve`, { token: tokens.mall_admin, body: {} });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.announcement.status, 'approved');
  assert.equal(ok.body.announcement.liveState, 'live');

  const twice = await call('POST', `/announcements/${id}/approve`, { token: tokens.mall_admin, body: {} });
  assert.equal(twice.status, 409);

  const liveAfter = await call('GET', '/announcements?live=live&pageSize=100', { token: tokens.store_owner });
  assert.ok(liveAfter.body.items.some((a) => a.id === id));
});

test('a store owner who loses the last store is deactivated and reactivated on re-assignment', async () => {
  const off = await call('POST', `/owners/${fx.ownerId}/unassign`, { token: tokens.mall_admin, body: { storeId: fx.storeA } });
  assert.equal(off.status, 200);
  assert.equal(off.body.deactivated, true);
  assert.equal(off.body.user.isActive, false);

  const login = await call('POST', '/auth/login', { body: { email: `store_owner.${tag}@test.local`, password: PASSWORD } });
  assert.equal(login.status, 403);

  const on = await call('POST', `/owners/${fx.ownerId}/assign`, { token: tokens.mall_admin, body: { storeId: fx.storeA } });
  assert.equal(on.status, 200);
  assert.equal(on.body.user.isActive, true);
  assert.equal(on.body.user.stores.length, 1);
});

test('an option list value in use can be deactivated but not deleted', async () => {
  const opt = await call('POST', '/options', { token: tokens.mall_admin, body: { branchId: fx.branchA, kind: 'store_category', name: `Cat ${tag}` } });
  assert.equal(opt.status, 201);
  const store = await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `S1 ${tag}`, categoryId: opt.body.option.id } });
  assert.equal(store.status, 201);

  const del = await call('DELETE', `/options/${opt.body.option.id}`, { token: tokens.mall_admin });
  assert.equal(del.status, 409);
  const off = await call('POST', `/options/${opt.body.option.id}/deactivate`, { token: tokens.mall_admin });
  assert.equal(off.status, 200);
  assert.equal(off.body.option.isActive, false);
  // The store keeps its category.
  const again = await call('GET', `/stores/${store.body.store.id}`, { token: tokens.mall_admin });
  assert.equal(again.body.store.categoryId, opt.body.option.id);
});

test('map: only the lock holder saves; a stale base version is refused; publish strips the backdrop', async () => {
  const created = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { width: 40, depth: 30 } });
  assert.equal(created.status, 201);
  const lock = await call('POST', `/maps/${fx.branchA}/lock`, { token: tokens.mall_admin });
  assert.equal(lock.status, 200);

  const get = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  const layout = get.body.map.draft;
  layout.buildings[0].levels[0].features.push({ id: 'ft-e', type: 'entrance', x: 1, z: 0 });
  layout.buildings[0].levels[0].spaces.push({ id: 'sp-1', name: 'Unit 1', type: 'retail', shape: { outer: [[1, 1], [5, 1], [5, 5], [1, 5]], holes: [] } });
  layout.buildings[0].levels[0].backdrop = { id: 'a'.repeat(32), cx: 20, cz: 15, mpp: 0.01, rot: 0, opacity: 0.5, locked: false };

  const save = await call('PUT', `/maps/${fx.branchA}/draft`, { token: tokens.mall_admin, body: { layout, baseVersion: get.body.map.draftVersion } });
  assert.equal(save.status, 200);
  const stale = await call('PUT', `/maps/${fx.branchA}/draft`, { token: tokens.mall_admin, body: { layout, baseVersion: get.body.map.draftVersion } });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.code, 'MAP_STALE');

  // A supervisor cannot lock or edit at all.
  const supLock = await call('POST', `/maps/${fx.branchA}/lock`, { token: tokens.supervisor });
  assert.equal(supLock.status, 403);

  const pub = await call('POST', `/maps/${fx.branchA}/publish`, { token: tokens.mall_admin, body: { baseVersion: save.body.draftVersion } });
  assert.equal(pub.status, 200, JSON.stringify(pub.body));
  const published = await call('GET', `/maps/${fx.branchA}/published`, { token: tokens.supervisor });
  assert.equal(published.status, 200);
  assert.equal(published.body.layout.buildings[0].levels[0].backdrop, undefined);
});

test('a dangling store link is reported as a warning, never a block', async () => {
  const store = await call('POST', '/stores', { token: tokens.mall_admin, body: { branchId: fx.branchA, name: `S2 ${tag}` } });
  const link = await call('PUT', `/stores/${store.body.store.id}/spaces`, { token: tokens.mall_admin, body: { spaceKeys: ['sp-gone'] } });
  assert.equal(link.status, 200);
  const get = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  assert.ok(get.body.warnings.some((w) => w.code === 'dangling_link' && w.message.includes(`S2 ${tag}`)));
});

test('a mall owner created with several malls and branches at once gets them all and a temporary password', async () => {
  // Found on the deployed Firestore system (2026-10-23): two or more places at once failed after the account was made.
  const r = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `owner2.${tag}@test.local`, fullName: 'Two Malls', role: 'supervisor', assignments: { mallIds: [fx.mallA, fx.mallB], branchIds: [fx.branchA] } },
  });
  assert.equal(r.status, 201);
  assert.ok(r.body.tempPassword, 'the temporary password is shown once');
  const detail = await call('GET', `/accounts/${r.body.user.id}`, { token: tokens.superadmin });
  assert.equal(detail.body.assignments.malls.length, 2);
  assert.equal(detail.body.assignments.branches.length, 1);
  // Changing the set later replaces it whole.
  const again = await call('PUT', `/assignments/supervisors/${r.body.user.id}`, { token: tokens.superadmin, body: { mallIds: [fx.mallB], branchIds: [fx.branchA, fx.branchB] } });
  assert.equal(again.status, 200);
  const after = await call('GET', `/accounts/${r.body.user.id}`, { token: tokens.superadmin });
  assert.equal(after.body.assignments.malls.length, 1);
  assert.equal(after.body.assignments.branches.length, 2);
});

test('accounts can be created with an initial assignment, and orphans are listed as unassigned', async () => {
  const withAssign = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `ma2.${tag}@test.local`, fullName: 'Second Admin', role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchA] } },
  });
  assert.equal(withAssign.status, 201);
  const detail = await call('GET', `/accounts/${withAssign.body.user.id}`, { token: tokens.superadmin });
  assert.equal(detail.body.assignments.branches.length, 1);

  const orphan = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `ma3.${tag}@test.local`, fullName: 'Orphan Admin', role: 'mall_admin' },
  });
  assert.equal(orphan.status, 201);
  const list = await call('GET', '/accounts?status=unassigned&pageSize=200', { token: tokens.superadmin });
  assert.ok(list.body.items.some((u) => u.id === orphan.body.user.id));
  assert.ok(!list.body.items.some((u) => u.id === withAssign.body.user.id));
  const orphanRow = list.body.items.find((u) => u.id === orphan.body.user.id);
  assert.equal(orphanRow.assignmentCount, 0);
  assert.deepEqual(orphanRow.access, { malls: 0, branches: 0, stores: 0 });

  const all = await call('GET', '/accounts?role=mall_admin&pageSize=200', { token: tokens.superadmin });
  const assignedRow = all.body.items.find((u) => u.id === withAssign.body.user.id);
  assert.equal(assignedRow.access.branches, 1);
  assert.equal(assignedRow.assignmentCount, 1);
});

test('a whole-mall supervisor assignment covers branches created later', async () => {
  const created = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `sup2.${tag}@test.local`, fullName: 'Second Supervisor', role: 'supervisor', assignments: { mallIds: [fx.mallA], branchIds: [] } },
  });
  assert.equal(created.status, 201);
  const list = await call('GET', '/accounts?role=supervisor&pageSize=200', { token: tokens.superadmin });
  const row = list.body.items.find((u) => u.id === created.body.user.id);
  assert.equal(row.access.malls, 1);
  assert.equal(row.access.branches, 0);

  // The supervisor must change the temp password before using the app.
  const first = await call('POST', '/auth/login', { body: { email: `sup2.${tag}@test.local`, password: created.body.tempPassword } });
  assert.equal(first.status, 200);
  const changed = await call('POST', '/auth/change-password', { token: first.body.token, body: { currentPassword: created.body.tempPassword, newPassword: PASSWORD } });
  assert.equal(changed.status, 200);
  const login = await call('POST', '/auth/login', { body: { email: `sup2.${tag}@test.local`, password: PASSWORD } });

  const later = await call('POST', '/branches', { token: tokens.superadmin, body: { mallId: fx.mallA, name: `Branch A2 ${tag}` } });
  assert.equal(later.status, 201);
  const seen = await call('GET', '/branches?pageSize=100', { token: login.body.token });
  assert.equal(seen.status, 200);
  assert.ok(seen.body.items.some((b) => b.id === later.body.branch.id), 'new branch is visible without a new assignment');
});

test('a mall admin manages exactly one branch; moving them replaces it', async () => {
  const two = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `ma4.${tag}@test.local`, fullName: 'Two-branch Admin', role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchA, fx.branchB] } },
  });
  assert.equal(two.status, 400);
  const created = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `ma4.${tag}@test.local`, fullName: 'One-branch Admin', role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchA] } },
  });
  assert.equal(created.status, 201);
  const id = created.body.user.id;
  const tooMany = await call('PUT', `/assignments/mall-admins/${id}`, { token: tokens.superadmin, body: { branchIds: [fx.branchA, fx.branchB] } });
  assert.equal(tooMany.status, 400);
  const moved = await call('PUT', `/assignments/mall-admins/${id}`, { token: tokens.superadmin, body: { branchIds: [fx.branchB] } });
  assert.equal(moved.status, 200);
  const detail = await call('GET', `/accounts/${id}`, { token: tokens.superadmin });
  assert.deepEqual(detail.body.assignments.branches.map((b) => b.id), [fx.branchB]);
  // Once placed, the admin is no longer offered to malls.
  const free = await call('GET', `/lookups/free_mall_admins?search=${tag}&pageSize=50`, { token: tokens.superadmin });
  assert.ok(!free.body.items.some((i) => i.id === id));
  // From the People page of mall A they cannot be taken while they manage a branch of mall B.
  const taken = await call('PUT', `/malls/${fx.mallA}/admins/${id}`, { token: tokens.superadmin, body: { branchIds: [fx.branchA] } });
  assert.equal(taken.status, 409);
});

test('mall impact counts active branches, active stores and distinct mall admins', async () => {
  const mall = await call('POST', '/malls', { token: tokens.superadmin, body: { name: `Mall C ${tag}` } });
  assert.equal(mall.status, 201);
  const branch = await call('POST', '/branches', { token: tokens.superadmin, body: { mallId: mall.body.mall.id, name: `Branch C ${tag}` } });
  assert.equal(branch.status, 201);
  for (const n of ['C1', 'C2']) {
    await db.insertStore(branch.body.branch.id, `Store ${n} ${tag}`);
  }
  const admin = await call('POST', '/accounts', {
    token: tokens.superadmin,
    body: { email: `ma5.${tag}@test.local`, fullName: 'Mall C Admin', role: 'mall_admin', assignments: { mallIds: [], branchIds: [branch.body.branch.id] } },
  });
  assert.equal(admin.status, 201);

  const impact = await call('GET', `/malls/${mall.body.mall.id}/impact`, { token: tokens.superadmin });
  assert.equal(impact.status, 200);
  assert.deepEqual(impact.body, { branches: 1, stores: 2, mallAdmins: 1 });

  const bImpact = await call('GET', `/branches/${branch.body.branch.id}/impact`, { token: tokens.superadmin });
  assert.deepEqual(bImpact.body, { stores: 2, storeOwners: 0, mallAdmins: 1 });
});

test('deactivating a mall hides its branches and stores from scoped roles and pickers', async () => {
  const impact = await call('GET', `/malls/${fx.mallA}/impact`, { token: tokens.superadmin });
  assert.equal(impact.status, 200);
  assert.ok(impact.body.branches >= 1);

  await call('POST', `/malls/${fx.mallA}/deactivate`, { token: tokens.superadmin });
  try {
    // Owner decision 2026-10-22 (Round 9): a mall owner keeps seeing their own malls and branches
    // after deactivation, so they can reactivate them. Their stores stay hidden (checked below).
    const sup = await call('GET', '/branches?pageSize=100', { token: tokens.supervisor });
    assert.ok(sup.body.items.some((b) => b.id === fx.branchA), 'the owner still sees the branch of their inactive mall');
    // Round 14 (owner decision 2026-10-22): the owner also sees that branch's stores, read-only.
    const supStores = await call('GET', '/stores?pageSize=100', { token: tokens.supervisor });
    assert.ok(supStores.body.items.some((s) => s.branchId === fx.branchA), 'and its stores, read-only');
    const ma = await call('GET', `/branches/${fx.branchA}`, { token: tokens.mall_admin });
    assert.equal(ma.status, 403);
    const owner = await call('GET', '/stores?pageSize=100', { token: tokens.store_owner });
    assert.equal(owner.body.items.length, 0);
    const pick = await call('GET', '/lookups/branches?pageSize=50', { token: tokens.superadmin });
    assert.ok(!pick.body.items.some((b) => b.id === fx.branchA), 'pickers must not offer branches of an inactive mall');
  } finally {
    await call('POST', `/malls/${fx.mallA}/reactivate`, { token: tokens.superadmin });
  }
  const back = await call('GET', `/branches/${fx.branchA}`, { token: tokens.mall_admin });
  assert.equal(back.status, 200);
});

test('session length follows the session_timeout_hours setting', async () => {
  await db.setSetting('session_timeout_hours', 2);
  settings.invalidate();
  try {
    const r = await call('POST', '/auth/login', { body: { email: `superadmin.${tag}@test.local`, password: PASSWORD } });
    const payload = JSON.parse(Buffer.from(r.body.token.split('.')[1], 'base64url').toString());
    const hours = (payload.exp - payload.iat) / 3600;
    assert.ok(Math.abs(hours - 2) < 0.01, `token lasts ${hours} h`);
  } finally {
    await db.setSetting('session_timeout_hours', 8);
    settings.invalidate();
  }
});


test('an option value can be read by id inside scope only', async () => {
  const opt = await call('POST', '/options', { token: tokens.mall_admin, body: { branchId: fx.branchA, kind: 'floor_label', name: `Floor ${tag}` } });
  assert.equal(opt.status, 201);
  const mine = await call('GET', `/options/${opt.body.option.id}`, { token: tokens.mall_admin });
  assert.equal(mine.status, 200);
  assert.equal(mine.body.option.name, `Floor ${tag}`);
  // An option on a branch the mall admin is not assigned to (branch B) is out of their scope.
  const other = await db.insertOption(fx.branchB, 'floor_label', `Other ${tag}`);
  const outsider = await call('GET', `/options/${other}`, { token: tokens.mall_admin });
  assert.equal(outsider.status, 403);
});
