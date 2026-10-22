// A branch with no map yet: the editor must be told who may create one, or
// its "Create map" button never shows (bug found by the owner, 2026-10-22).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';

const tag = `m${Date.now().toString(36)}`;
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

test('no map yet: the mall admin and the superadmin are told they may create one, the owner is not', async () => {
  const admin = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  assert.equal(admin.status, 200);
  assert.equal(admin.body.map, null);
  assert.equal(admin.body.canEdit, true);

  const superadmin = await call('GET', `/maps/${fx.branchB}`, { token: tokens.superadmin });
  assert.equal(superadmin.body.map, null);
  assert.equal(superadmin.body.canEdit, true);

  const owner = await call('GET', `/maps/${fx.branchA}`, { token: tokens.supervisor });
  assert.equal(owner.body.map, null);
  assert.equal(owner.body.canEdit, false);
});

test('the mall admin creates the map, and the branch then has it', async () => {
  const created = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { buildingName: 'Main building', levelName: 'Ground floor', width: 120, depth: 80 } });
  assert.equal(created.status, 201, JSON.stringify(created.body));

  const again = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  assert.ok(again.body.map, 'the map now exists');
  assert.equal(again.body.map.draft.buildings[0].name, 'Main building');
  assert.equal(again.body.canEdit, true);

  const twice = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: {} });
  assert.equal(twice.status, 409);
});

// Round 17: a map started from an uploaded plan has no made-up rectangle; its
// floor outline comes from the plan (owner decision 2026-10-22).
test('a map can start without a floor outline; the default still has one', async () => {
  const created = await call('POST', `/maps/${fx.branchB}`, { token: tokens.superadmin, body: { outline: false } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const map = await call('GET', `/maps/${fx.branchB}`, { token: tokens.superadmin });
  const level = map.body.map.draft.buildings[0].levels[0];
  assert.equal(level.outline, null);
  assert.equal(level.name, 'Ground floor');
  assert.equal(map.body.map.draft.buildings[0].name, 'Main building');

  const a = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  assert.ok(a.body.map.draft.buildings[0].levels[0].outline, 'the hand-made map keeps its rectangle');
});
