// Problem reports and the Requests & reports counts (Round 19, owner
// decisions 2026-10-23): mall owners, mall admins and store owners report; the
// superadmin answers in a thread and moves the report on; all audited.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import { query } from '../src/db/pool.js';

const tag = `rp${Date.now()}`;
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

const report = (token, body = {}) =>
  call('POST', '/reports', { token, body: { type: 'broken', subject: 'Map does not save', body: 'Saving the draft shows an error.', pagePath: '/mall-admin/maps', ...body } });

test('mall owners, mall admins and store owners can report; superadmins cannot', async () => {
  for (const role of ['supervisor', 'mall_admin', 'store_owner']) {
    const r = await report(tokens[role]);
    assert.equal(r.status, 201, `${role}: ${JSON.stringify(r.body)}`);
    assert.equal(r.body.report.status, 'new');
    assert.equal(r.body.report.pagePath, '/mall-admin/maps');
  }
  assert.equal((await report(tokens.superadmin)).status, 400);
  assert.equal((await report(tokens.mall_admin, { type: 'other' })).status, 400, 'only the four types');
  assert.equal((await report(tokens.mall_admin, { subject: 'x'.repeat(121) })).status, 400);
});

test('a reporter sees only their own reports; the superadmin sees all, with filters', async () => {
  const mine = await call('GET', '/reports/mine', { token: tokens.store_owner });
  assert.equal(mine.status, 200);
  assert.ok(mine.body.items.length >= 1 && mine.body.items.every((x) => x.reporterId === fx.ownerId));
  const other = mine.body.items[0].id;
  assert.equal((await call('GET', `/reports/${other}`, { token: tokens.mall_admin })).status, 404, "another person's report is not found");
  assert.equal((await call('GET', '/reports', { token: tokens.mall_admin })).status, 403);
  const all = await call('GET', '/reports?status=waiting&type=broken&pageSize=100', { token: tokens.superadmin });
  assert.ok(all.body.items.filter((x) => x.reporterEmail.endsWith(`${tag}@test.local`)).length >= 3);
  assert.ok(all.body.items.every((x) => x.waiting && x.type === 'broken'));
});

test('a thread until it is resolved; statuses only move forward; every step audited', async () => {
  const r = (await report(tokens.mall_admin, { type: 'question', subject: 'How do I add a level?' })).body.report;
  const reply = (token, body) => call('POST', `/reports/${r.id}/messages`, { token, body: { body } });
  let x = await reply(tokens.superadmin, 'Open Structure and press Add level.');
  assert.equal(x.status, 201);
  assert.equal(x.body.report.waiting, true, 'still new until moved on');
  x = await call('PUT', `/reports/${r.id}/status`, { token: tokens.superadmin, body: { status: 'in_progress' } });
  assert.equal(x.body.report.status, 'in_progress');
  assert.equal(x.body.report.waiting, false, 'the superadmin answered last');
  x = await reply(tokens.mall_admin, 'Found it, thanks. One more: can I rename it?');
  assert.equal(x.body.report.waiting, true, 'the reporter wrote last');
  assert.deepEqual(x.body.messages.map((m) => m.authorRole), ['superadmin', 'mall_admin']);
  assert.equal((await call('PUT', `/reports/${r.id}/status`, { token: tokens.mall_admin, body: { status: 'resolved' } })).status, 403);
  x = await call('PUT', `/reports/${r.id}/status`, { token: tokens.superadmin, body: { status: 'resolved' } });
  assert.equal(x.body.report.status, 'resolved');
  assert.ok(x.body.report.closedBy);
  assert.equal((await reply(tokens.mall_admin, 'Another thing')).status, 409, 'no messages once resolved');
  assert.equal((await call('PUT', `/reports/${r.id}/status`, { token: tokens.superadmin, body: { status: 'in_progress' } })).status, 409, 'no going back');
  const actions = (await query(`SELECT action FROM audit_log WHERE entity_type = 'problem_report' AND entity_id = @id`, { id: String(r.id) })).recordset.map((a) => a.action);
  for (const a of ['problem_reported', 'problem_report_message', 'problem_report_status']) assert.ok(actions.includes(a), a);
});

test('the counts: profile changes, AI credits and reports waiting, and the total', async () => {
  const c = await call('GET', '/requests/counts', { token: tokens.superadmin });
  assert.equal(c.status, 200);
  assert.ok(c.body.reports >= 3);
  assert.equal(c.body.total, c.body.profile + c.body.credits + c.body.reports);
  assert.equal((await call('GET', '/requests/counts', { token: tokens.supervisor })).status, 403);
});
