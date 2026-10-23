// AI credits per mall admin (Round 19, owner decisions 2026-10-23): start
// credits, the cap, never more than the wallet, requests, readings, return on
// deactivation, who sees what, and the audit trail.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import { config } from '../src/config.js';
import * as db from './support/testDb.js';
import * as settings from '../src/repos/settings.js';
import * as credits from '../src/repos/credits.js';
import { walletSplit, refuseGive, refuseRemove, startCredits } from '../src/ai/credits.js';
import { assertCanRead, chargeReading } from '../src/ai/creditOps.js';

const tag = `cr${Date.now()}`;
let server;
let call;
let fx;
const tokens = {};
let saved;
let savedSettings;
let fakeGateway;

// The fake wallet is "what admins hold now + margin", read live, so other test
// files giving their own fixture admins credits at the same time cannot upset it.
let margin = 1000;
let blocked = false;

const balance = async (userId) => (await credits.balanceOf(userId)).balance;

before(async () => {
  fakeGateway = http.createServer(async (req, res) => {
    const given = await credits.givenTotal();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ enforced: true, blocked, reason: blocked ? 'Out of credits.' : null, balance: given + margin, daily: {} }));
  });
  await new Promise((r) => fakeGateway.listen(0, '127.0.0.1', r));
  saved = { ...config.ai };
  config.ai.key = 'test-key-credits';
  config.ai.url = `http://127.0.0.1:${fakeGateway.address().port}/v1`;
  const s = await startServer();
  server = s.server;
  call = api(s.base);
  fx = await makeFixtures(tag);
  for (const role of ['superadmin', 'supervisor', 'mall_admin', 'store_owner']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
  savedSettings = { ai_start_credits: await settings.getText('ai_start_credits'), ai_credit_cap: await settings.getText('ai_credit_cap') };
  await settings.setMany({ ai_start_credits: 3, ai_credit_cap: 20 }, null);
});

after(async () => {
  await settings.setMany(savedSettings, null);
  await cleanFixtures(tag);
  Object.assign(config.ai, saved);
  await new Promise((r) => fakeGateway.close(r));
  await stopServer(server);
});

const newAdmin = async (token, name) =>
  call('POST', '/accounts', {
    token,
    body: { email: `${name}.${tag}@test.local`, fullName: `${name} ${tag}`, role: 'mall_admin', assignments: { mallIds: [], branchIds: [fx.branchA] } },
  });

test('rules: the wallet split, giving, taking back and starting credits', () => {
  assert.deepEqual(walletSplit({ wallet: 82, given: 36, used: 18 }), { wallet: 82, given: 36, free: 46, used: 18, overGiven: 0 });
  assert.deepEqual(walletSplit({ wallet: 30, given: 35 }), { wallet: 30, given: 35, free: 0, used: 0, overGiven: 5 });
  assert.equal(walletSplit({ wallet: null, given: 4 }).free, null);
  assert.equal(refuseGive({ amount: 5, balance: 0, cap: 20, wallet: 100, given: 0 }), null);
  assert.match(refuseGive({ amount: 16, balance: 5, cap: 20, wallet: 100, given: 5 }), /At most 15 more/);
  assert.match(refuseGive({ amount: 1, balance: 20, cap: 20, wallet: 100, given: 20 }), /already has the most/);
  assert.match(refuseGive({ amount: 5, balance: 0, cap: 20, wallet: 10, given: 8 }), /Only 2 credits are free/);
  assert.match(refuseGive({ amount: 1, balance: 0, cap: 20, wallet: 10, given: 12 }), /more credits than the wallet/);
  assert.match(refuseGive({ amount: 1, balance: 0, cap: 20, wallet: null, given: 0 }), /could not be checked/);
  assert.equal(refuseRemove({ amount: 2, balance: 3 }), null);
  assert.match(refuseRemove({ amount: 4, balance: 3 }), /only has 3/);
  assert.deepEqual(startCredits({ start: 3, cap: 20, wallet: 100, given: 0 }), { amount: 3, note: null });
  assert.equal(startCredits({ start: 3, cap: 20, wallet: 10, given: 8.8 }).amount, 1.2);
  assert.match(startCredits({ start: 3, cap: 20, wallet: 10, given: 8.8 }).note, /Started with 1.2/);
  assert.equal(startCredits({ start: 3, cap: 20, wallet: 5, given: 9 }).amount, 0);
  assert.match(startCredits({ start: 3, cap: 20, wallet: null, given: 0 }).note, /could not be checked/);
});

test('a new mall admin starts with 3 credits; an existing one has 0', async () => {
  assert.equal(await balance(fx.mallAdminId), 0, 'existing admins start at 0');
  margin = 1000;
  const r = await newAdmin(tokens.superadmin, 'fresh');
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.startCredits, 3);
  assert.equal(r.body.startNote, null);
  assert.equal(await balance(r.body.user.id), 3);
  const led = await db.ledger(r.body.user.id);
  assert.deepEqual(led.map((x) => [x.kind, x.delta]), [['start', 3]]);
  // A mall owner creating an admin in their branch: the same.
  const o = await newAdmin(tokens.supervisor, 'ownermade');
  assert.equal(o.status, 201, JSON.stringify(o.body));
  assert.equal(o.body.startCredits, 3);
});

test('when fewer than 3 are free, the account is still created with what is free', async () => {
  margin = 1.2;
  const r = await newAdmin(tokens.superadmin, 'short');
  margin = 1000;
  assert.equal(r.status, 201);
  assert.ok(r.body.startCredits <= 1.2 && r.body.startCredits >= 0);
  assert.match(r.body.startNote, /Started with|starts with 0/);
});

test('giving and taking back: the cap of 20, never below 0, audited', async () => {
  margin = 1000;
  const give = (delta, token = tokens.superadmin) => call('POST', `/ai/credits/${fx.mallAdminId}/adjust`, { token, body: { delta, note: 'for the test' } });
  assert.equal((await give(5)).body.balance, 5);
  const over = await give(16);
  assert.equal(over.status, 409);
  assert.match(over.body.error, /At most 15 more/);
  assert.equal((await give(15)).body.balance, 20);
  const tooMuch = await give(-25);
  assert.equal(tooMuch.status, 409);
  assert.match(tooMuch.body.error, /only has 20/);
  assert.equal((await give(-2)).body.balance, 18);
  assert.equal((await give(1, tokens.mall_admin)).status, 403, 'admins cannot give themselves credits');
  assert.equal((await give(1, tokens.supervisor)).status, 403, 'owners cannot give credits');
  const audit = await db.auditRows({ actorEmail: `superadmin.${tag}@test.local`, actions: ['ai_credits_granted', 'ai_credits_removed'] });
  assert.ok(audit.some((x) => x.action === 'ai_credits_granted'));
  assert.ok(audit.some((x) => x.action === 'ai_credits_removed'));
  // Only active mall admins hold credits.
  const owner = await call('POST', `/ai/credits/${fx.supervisorId}/adjust`, { token: tokens.superadmin, body: { delta: 1 } });
  assert.equal(owner.status, 400);
});

test('never more than the wallet; when over-given, nothing more can be given', async () => {
  const fresh = await newAdmin(tokens.superadmin, 'walletcheck');
  const id = fresh.body.user.id;
  margin = 2;
  const r = await call('POST', `/ai/credits/${id}/adjust`, { token: tokens.superadmin, body: { delta: 5 } });
  assert.equal(r.status, 409);
  assert.match(r.body.error, /free/);
  margin = -10;
  const o = await call('POST', `/ai/credits/${id}/adjust`, { token: tokens.superadmin, body: { delta: 1 } });
  assert.equal(o.status, 409);
  assert.match(o.body.error, /more credits than the wallet/);
  const ov = await call('GET', '/ai/credits/overview?days=7', { token: tokens.superadmin });
  assert.ok(ov.body.wallet.overGiven > 0, 'the superadmin sees it is over-given');
  margin = 1000;
});

test('requests: an amount, one at a time; cancel, approve (maybe less) and decline', async () => {
  margin = 1000;
  const made = await newAdmin(tokens.superadmin, 'asker');
  const id = made.body.user.id;
  const login = await call('POST', '/auth/login', { body: { email: `asker.${tag}@test.local`, password: made.body.tempPassword } });
  await call('POST', '/auth/change-password', { token: login.body.token, body: { currentPassword: made.body.tempPassword, newPassword: PASSWORD } });
  const t = (await call('POST', '/auth/login', { body: { email: `asker.${tag}@test.local`, password: PASSWORD } })).body.token;

  const tooBig = await call('POST', '/ai/credits/requests', { token: t, body: { amount: 18 } });
  assert.equal(tooBig.status, 400, 'at most cap − balance (17)');
  const first = await call('POST', '/ai/credits/requests', { token: t, body: { amount: 10 } });
  assert.equal(first.status, 201, JSON.stringify(first.body));
  assert.equal((await call('POST', '/ai/credits/requests', { token: t, body: { amount: 2 } })).status, 409, 'one at a time');
  assert.equal((await call('DELETE', '/ai/credits/requests/mine', { token: t })).status, 200);

  const second = await call('POST', '/ai/credits/requests', { token: t, body: { amount: 4 } });
  const counts = await call('GET', '/requests/counts', { token: tokens.superadmin });
  assert.ok(counts.body.credits >= 1 && counts.body.total >= counts.body.credits);
  const detail = await call('GET', `/ai/credits/requests/${second.body.request.id}`, { token: tokens.superadmin });
  assert.equal(detail.body.limits.room, 17);
  assert.equal((await call('POST', `/ai/credits/requests/${second.body.request.id}/approve`, { token: tokens.supervisor, body: {} })).status, 403);
  assert.equal((await call('POST', `/ai/credits/requests/${second.body.request.id}/approve`, { token: tokens.superadmin, body: { amount: 6 } })).status, 400, 'not more than asked');
  const ok = await call('POST', `/ai/credits/requests/${second.body.request.id}/approve`, { token: tokens.superadmin, body: { amount: 2 } });
  assert.equal(ok.status, 200, JSON.stringify(ok.body));
  assert.equal(ok.body.request.status, 'approved');
  assert.equal(ok.body.request.decidedAmount, 2);
  assert.equal(await balance(id), 5);
  assert.equal((await call('POST', `/ai/credits/requests/${second.body.request.id}/decline`, { token: tokens.superadmin, body: {} })).status, 409, 'already decided');

  const third = await call('POST', '/ai/credits/requests', { token: t, body: { amount: 1 } });
  const no = await call('POST', `/ai/credits/requests/${third.body.request.id}/decline`, { token: tokens.superadmin, body: { reason: 'Enough for now.' } });
  assert.equal(no.body.request.status, 'declined');
  const mine = await call('GET', '/ai/credits/mine', { token: t });
  assert.equal(mine.body.balance, 5);
  assert.equal(mine.body.cap, 20);
  assert.equal(mine.body.request.status, 'declined');
  const audit = await db.auditRows({ actionPrefix: 'ai_credit_request', entityId: id });
  for (const a of ['ai_credit_requested', 'ai_credit_request_cancelled', 'ai_credit_request_approved', 'ai_credit_request_declined']) {
    assert.ok(audit.some((x) => x.action === a), a);
  }
});

test('readings: blocked at 0, the cost comes off after, and may end below 0', async () => {
  const admin = { id: fx.mallAdminId, role: 'mall_admin' };
  await credits.withCreditsLock((tx) => credits.change(tx, { userId: fx.mallAdminId, delta: -(18 - 0.05), kind: 'remove' }));
  await assertCanRead(admin);
  const after = await chargeReading(admin, 0.08, null);
  assert.equal(after, -0.03, 'a little below 0 is allowed');
  await assert.rejects(assertCanRead(admin), /no AI credits left/);
  // A superadmin reads from the free part only.
  margin = 0;
  await assert.rejects(assertCanRead({ id: fx.superadminId, role: 'superadmin' }), /given to mall admins/);
  margin = 1000;
  await assertCanRead({ id: fx.superadminId, role: 'superadmin' });
});

test('deactivating returns the credits and closes the request; reactivating starts again', async () => {
  margin = 1000;
  const made = await newAdmin(tokens.superadmin, 'leaver');
  const id = made.body.user.id;
  await credits.createRequest(id, 2);
  const d = await call('POST', `/accounts/${id}/deactivate`, { token: tokens.superadmin });
  assert.equal(d.status, 200, JSON.stringify(d.body));
  assert.equal(await balance(id), 0);
  assert.equal((await credits.latestRequestFor(id)).status, 'cancelled');
  const r = await call('POST', `/accounts/${id}/reactivate`, { token: tokens.superadmin });
  assert.equal(r.body.startCredits, 3);
  assert.equal(await balance(id), 3);
  const kinds = (await db.ledger(id)).map((x) => x.kind);
  assert.deepEqual(kinds, ['start', 'returned', 'start']);
});

test('who sees what: the superadmin everything; an owner their admins only; admins only their own', async () => {
  const s = await call('GET', '/ai/credits/overview?days=30', { token: tokens.superadmin });
  assert.equal(s.status, 200);
  assert.ok(s.body.wallet && typeof s.body.wallet.free === 'number');
  assert.ok(s.body.admins.some((a) => a.id === fx.mallAdminId));
  assert.ok(Array.isArray(s.body.requests.items));
  const o = await call('GET', '/ai/credits/overview?days=30', { token: tokens.supervisor });
  assert.equal(o.status, 200);
  assert.equal(o.body.wallet, null);
  assert.equal(o.body.requests, null);
  assert.ok(o.body.admins.length >= 1 && o.body.admins.every((a) => a.email.endsWith(`${tag}@test.local`)));
  assert.equal((await call('GET', '/ai/credits/overview', { token: tokens.mall_admin })).status, 403);
  assert.equal((await call('GET', '/ai/credits/history', { token: tokens.supervisor })).status, 403);
  const h = await call('GET', `/ai/credits/history?userId=${fx.mallAdminId}&pageSize=50`, { token: tokens.superadmin });
  assert.ok(h.body.totalCount >= 4);
  assert.ok(h.body.items.every((x) => x.userId === fx.mallAdminId));
  assert.equal((await call('GET', '/ai/credits/mine', { token: tokens.supervisor })).status, 403);
});

test('the starting credits and the cap are settings with ranges', async () => {
  const bad = await call('PUT', '/settings', { token: tokens.superadmin, body: { ai_credit_cap: 0 } });
  assert.equal(bad.status, 400);
  const ok = await call('PUT', '/settings', { token: tokens.superadmin, body: { ai_start_credits: 3, ai_credit_cap: 20 } });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.rules.ai_credit_cap.label, 'Most AI credits per mall admin');
});
