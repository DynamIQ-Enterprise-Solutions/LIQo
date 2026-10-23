// Round 15: floor plans are read by AI through IQGateway (owner decisions 2026-10-22).
// A fake gateway on a random port answers instead of the real one: no credits are spent.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, giveTestCredits, PASSWORD } from './helpers.js';
import { config } from '../src/config.js';
import { query, sql } from '../src/db/pool.js';
import * as settings from '../src/repos/settings.js';
import * as gateway from '../src/ai/gateway.js';

const tag = `ai${Date.now().toString(36)}`;
const KEY = 'gws_test_only_not_a_real_key';
const UPLOADS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../uploads/backdrops');

let server;
let base;
let call;
let fx;
const tokens = {};
let saved;
let previousModel;
let previousWallet;
let uploadKey;
let levelId;

// ---- the fake gateway ----
const seen = [];
let reply = () => ({ status: 200, body: {} });
let fakeGateway;

function chatAnswer(content, extra = {}) {
  return {
    status: 200,
    body: {
      id: 'chatcmpl-test',
      model: 'test-vision-1',
      choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: 'stop' }],
      x_gateway: { credits: 0.5, usd: 0.004, tenant: 'test' },
      ...extra,
    },
  };
}

// A 20 × 14 m picture placed with its centre at (10, 7): picture metres = level metres.
// 0–1000 units: x × 20 m / 1000, y × 14 m / 1000.
const ux = (m) => (m / 20) * 1000;
const uy = (m) => (m / 14) * 1000;

function planAnswer() {
  return {
    isFloorPlan: true,
    outline: [
      { x: ux(2), y: uy(2) },
      { x: ux(18), y: uy(2) },
      { x: ux(18), y: uy(12) },
      { x: ux(2), y: uy(12) },
    ],
    walls: [
      // Top wall drawn slightly tilted: straightened onto one line.
      { x1: ux(2), y1: uy(2), x2: ux(18), y2: uy(2.03), kind: 'boundary', sure: true },
      { x1: ux(18.1), y1: uy(2), x2: ux(18.1), y2: uy(12), kind: 'boundary', sure: true },
      { x1: ux(18), y1: uy(12), x2: ux(2), y2: uy(12), kind: 'boundary', sure: true },
      // Left wall stops 15 cm short of the corner: snapped onto the top wall.
      { x1: ux(2), y1: uy(2.15), x2: ux(2), y2: uy(12), kind: 'boundary', sure: true },
      // Partition at x = 10 m with a 1 m door in the middle.
      { x1: ux(10), y1: uy(2), x2: ux(10), y2: uy(12), kind: 'partition', sure: true },
      // A 4 cm scrap: dropped.
      { x1: ux(5), y1: uy(5), x2: ux(5.04), y2: uy(5), kind: 'solid', sure: true },
    ],
    doors: [
      { x1: ux(10), y1: uy(6.5), x2: ux(10), y2: uy(7.5), kind: 'door', sure: true },
      // Nowhere near a wall: dropped.
      { x1: ux(6), y1: uy(7), x2: ux(7), y2: uy(7), kind: 'door', sure: true },
    ],
    rooms: [
      { name: `STORE A ${tag.toUpperCase()}`, type: 'retail', polygon: [{ x: ux(2), y: uy(2) }, { x: ux(10), y: uy(2) }, { x: ux(10), y: uy(12) }, { x: ux(2), y: uy(12) }], sure: true },
      { name: '', type: 'retail', polygon: [{ x: ux(10), y: uy(2) }, { x: ux(18), y: uy(2) }, { x: ux(18), y: uy(12) }, { x: ux(10), y: uy(12) }], sure: false },
    ],
    notes: 'Right unit has no readable label.',
  };
}

function blankPng(w, h) {
  const png = new PNG({ width: w, height: h });
  png.data.fill(255);
  return PNG.sync.write(png);
}

before(async () => {
  fakeGateway = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const entry = { method: req.method, url: req.url, auth: req.headers.authorization, body: body ? JSON.parse(body) : null };
      seen.push(entry);
      const out = reply(entry);
      res.writeHead(out.status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(out.body));
    });
  });
  await new Promise((r) => fakeGateway.listen(0, '127.0.0.1', r));
  saved = { ...config.ai };
  config.ai.key = KEY;
  config.ai.url = `http://127.0.0.1:${fakeGateway.address().port}/v1`;

  const s = await startServer();
  server = s.server;
  base = s.base;
  call = api(base);
  fx = await makeFixtures(tag);
  // Owner decision 2026-10-23 (Round 19): a mall admin reads plans only with AI credits.
  await giveTestCredits(fx.mallAdminId, 100);
  for (const role of ['superadmin', 'supervisor', 'mall_admin']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
  previousModel = await settings.getText('ai_model');
  // The credit bar's full mark lives in the real settings; keep the owner's and start clean.
  previousWallet = { ai_wallet_full: await settings.getText('ai_wallet_full'), ai_wallet_last: await settings.getText('ai_wallet_last') };
  await settings.setMany({ ai_wallet_full: '', ai_wallet_last: '' }, null);

  // A map, a lock, an uploaded plan placed on the level at 1 cm per pixel.
  const created = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { buildingName: 'Main', levelName: 'Ground', width: 20, depth: 14 } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  assert.equal((await call('POST', `/maps/${fx.branchA}/lock`, { token: tokens.mall_admin })).status, 200);
  const form = new FormData();
  form.append('file', new Blob([blankPng(2000, 1400)], { type: 'image/png' }), 'plan.png');
  const up = await fetch(`${base}/maps/${fx.branchA}/backdrops`, { method: 'POST', headers: { Authorization: `Bearer ${tokens.mall_admin}` }, body: form });
  const upBody = await up.json();
  assert.equal(up.status, 201, JSON.stringify(upBody));
  uploadKey = upBody.backdrop.id;
  const bundle = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  const layout = bundle.body.map.draft;
  const level = layout.buildings[0].levels[0];
  levelId = level.id;
  level.outline = null;
  // calibrated: the scale was set by hand. Round 18 (owner decision 2026-10-22:
  // "AI finds the scale itself") only changes the scale of plans never calibrated.
  level.backdrop = { id: uploadKey, cx: 10, cz: 7, mpp: 0.01, rot: 0, opacity: 0.5, locked: false, calibrated: true };
  const put = await call('PUT', `/maps/${fx.branchA}/draft`, { token: tokens.mall_admin, body: { layout, baseVersion: bundle.body.map.draftVersion } });
  assert.equal(put.status, 200, JSON.stringify(put.body));
});

after(async () => {
  await settings.setMany({ ai_model: previousModel ?? '' }, fx?.superadminId ?? 0);
  if (previousWallet) await settings.setMany(previousWallet, null);
  Object.assign(config.ai, saved);
  if (uploadKey) for (const ext of ['png', 'jpg']) fs.rmSync(path.join(UPLOADS, `${uploadKey}.${ext}`), { force: true });
  await cleanFixtures(tag);
  await stopServer(server);
  await new Promise((r) => fakeGateway.close(r));
});

const convert = (body = { levelId }) => call('POST', `/maps/${fx.branchA}/backdrops/${uploadKey}/convert`, { token: tokens.mall_admin, body });

test('model list is for superadmins; choosing a model checks it against the gateway', async () => {
  reply = (e) =>
    e.url === '/v1/models'
      ? {
          status: 200,
          body: {
            object: 'list',
            data: [
              { id: 'test-vision-1', owned_by: 'openai', type: 'chat', label: 'Test Vision 1', available: true },
              { id: 'test-vision-2', owned_by: 'gemini', type: 'chat', label: 'Test Vision 2', available: true },
              { id: 'test-off', owned_by: 'anthropic', type: 'chat', label: 'Switched off', available: false },
              { id: 'test-image', owned_by: 'gemini', type: 'image', label: 'Makes pictures', available: true },
            ],
          },
        }
      : { status: 404, body: {} };
  const list = await call('GET', '/ai/models', { token: tokens.superadmin });
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.items.map((m) => m.id), ['test-vision-1', 'test-vision-2'], 'only available chat models can read plans');
  assert.equal(list.body.items[0].label, 'Test Vision 1');
  assert.equal((await call('GET', '/ai/models', { token: tokens.mall_admin })).status, 403);

  assert.equal((await call('PUT', '/ai/model', { token: tokens.superadmin, body: { model: 'not-offered' } })).status, 400);
  assert.equal((await call('PUT', '/ai/model', { token: tokens.superadmin, body: { model: 'test-image' } })).status, 400, 'a picture-making model cannot read plans');
  assert.equal((await call('PUT', '/ai/model', { token: tokens.superadmin, body: { model: 'test-off' } })).status, 400, 'a model the gateway switched off');
  assert.equal((await call('PUT', '/ai/model', { token: tokens.mall_admin, body: { model: 'test-vision-1' } })).status, 403);
  const ok = await call('PUT', '/ai/model', { token: tokens.superadmin, body: { model: 'test-vision-1' } });
  assert.equal(ok.status, 200);
  assert.equal(await settings.getText('ai_model'), 'test-vision-1');
  const audit = await query(`SELECT details FROM audit_log WHERE action = 'ai_model_changed' AND actor_email = @e`, { e: `superadmin.${tag}@test.local` });
  assert.equal(audit.recordset.length, 1);

  // The gateway key never travels to the browser.
  assert.ok(!JSON.stringify(list.body).includes(KEY));
  assert.ok(seen.every((r) => r.auth === `Bearer ${KEY}`), 'every gateway call carries the server key');
});

// Owner decisions 2026-10-23: the wallet carries `full` (the last top-up) for the
// credit bar, and given/free/overGiven (Round 19). Mall admins never see the
// wallet's numbers, only their own credits.
test('status: superadmins see the wallet; mall admins only their own credits; owners nothing', async () => {
  reply = (e) => (e.url === '/v1/quota' ? { status: 200, body: { enforced: true, blocked: false, reason: null, balance: 120.5, daily: { usedTokens: 900, limitTokens: 0, usedCredits: 3.5, limitCredits: 50 } } } : { status: 404, body: {} });
  const r = await call('GET', '/ai/status', { token: tokens.superadmin });
  assert.equal(r.status, 200);
  assert.equal(r.body.configured, true);
  assert.equal(r.body.model, 'test-vision-1');
  const { given, free, overGiven, ...rest } = r.body.quota;
  assert.deepEqual(rest, { balance: 120.5, usedToday: 3.5, dailyCap: 50, blocked: false, reason: null, full: 120.5 });
  assert.ok(given >= 100, 'the fixture admin holds 100');
  assert.equal(free, Math.max(0, Math.round((120.5 - given) * 10000) / 10000));
  assert.ok(overGiven >= 0);
  const mine = await call('GET', '/ai/status', { token: tokens.mall_admin });
  assert.equal(mine.status, 200);
  assert.equal(mine.body.quota, null, 'no wallet numbers for mall admins');
  assert.equal(mine.body.mine.balance, 100);
  assert.equal(mine.body.gatewayBlocked, false);
  assert.equal((await call('GET', '/ai/status', { token: tokens.supervisor })).status, 403);
});

test('credit bar: the full mark is the balance after the last top-up', async () => {
  const wallet = async (balance) => {
    reply = (e) => (e.url === '/v1/quota' ? { status: 200, body: { blocked: false, balance, daily: {} } } : { status: 404, body: {} });
    // Round 19: only superadmins see the wallet.
    const r = await call('GET', '/ai/status', { token: tokens.superadmin });
    assert.equal(r.status, 200);
    return r.body.quota.full;
  };
  await settings.setMany({ ai_wallet_full: '', ai_wallet_last: '' }, null);
  assert.equal(await wallet(80), 80, 'the first balance seen counts as full');
  assert.equal(await wallet(60), 80, 'spending keeps the mark');
  assert.equal(await wallet(30), 80);
  assert.equal(await wallet(90), 90, 'a rise is a top-up: full again');
  assert.equal(await wallet(85), 90);
});

test('credit bar: walletMark rules', () => {
  assert.equal(gateway.walletMark(null, null), null);
  assert.deepEqual(gateway.walletMark(null, 10), { full: 10, last: 10 });
  assert.deepEqual(gateway.walletMark({ full: 10, last: 4 }, 3), { full: 10, last: 3 });
  assert.deepEqual(gateway.walletMark({ full: 10, last: 4 }, 6), { full: 6, last: 6 });
  assert.deepEqual(gateway.walletMark({ full: 10, last: 4 }, null), { full: 10, last: 4 });
});

test('reading a plan: the picture and schema go to the gateway; a tidy proposal comes back', async () => {
  seen.length = 0;
  reply = () => chatAnswer(JSON.stringify(planAnswer()));
  const before = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  const r = await convert();
  assert.equal(r.status, 200, JSON.stringify(r.body));

  // What the gateway was sent.
  assert.equal(seen.length, 1);
  const sent = seen[0].body;
  assert.equal(seen[0].url, '/v1/chat/completions');
  assert.equal(sent.model, 'test-vision-1');
  assert.equal(sent.response_format.type, 'json_schema');
  const user = sent.messages.find((m) => m.role === 'user');
  const img = user.content.find((p) => p.type === 'image_url');
  assert.match(img.image_url.url, /^data:image\/png;base64,/);
  const png = PNG.sync.read(Buffer.from(img.image_url.url.split(',')[1], 'base64'));
  assert.ok(Math.max(png.width, png.height) <= 2000);
  const textPart = user.content.find((p) => p.type === 'text').text;
  assert.match(textPart, /20\.0 m wide and 14\.0 m tall/);
  assert.match(textPart, new RegExp(`Store A ${tag}`), 'store names are given for spelling');

  // The proposal.
  const p = r.body.proposal;
  assert.equal(r.body.usedAi, true);
  assert.equal(p.levelId, levelId);
  assert.equal(p.walls.length, 5, 'the 4 cm scrap is dropped');
  const top = p.walls.find((w) => Math.abs(w.a[1] - 2) < 0.1 && Math.abs(w.b[1] - 2) < 0.1);
  assert.ok(top, 'top wall found');
  assert.equal(top.a[1], top.b[1], 'a slightly tilted wall is straightened');
  const left = p.walls.find((w) => Math.abs(w.a[0] - 2) < 0.1 && Math.abs(w.b[0] - 2) < 0.1);
  assert.equal(left.a[1], top.a[1], 'the short left wall is snapped into the corner');
  const right = p.walls.find((w) => Math.abs(w.a[0] - 18) < 0.2 && Math.abs(w.b[0] - 18) < 0.2);
  assert.equal(top.b[0], right.a[0], 'the corner is shared exactly');
  assert.ok(p.walls.every((w) => w.id.startsWith('ai-')));

  assert.equal(p.openings.length, 1, 'the door far from any wall is dropped');
  const door = p.openings[0];
  const partition = p.walls.find((w) => w.id === door.wall);
  assert.equal(partition.kind, 'partition');
  assert.ok(Math.abs(door.w - 1) < 0.05, `door width ${door.w}`);
  assert.ok(Math.abs(door.at - 0.5) < 0.02, `door position ${door.at}`);

  assert.equal(p.spaces.length, 2);
  const named = p.spaces.find((s) => s.name);
  const unnamed = p.spaces.find((s) => !s.name);
  assert.ok(p.uncertain.includes(unnamed.id), 'the unsure room is marked');
  assert.ok(!p.uncertain.includes(named.id));
  assert.deepEqual(p.storeMatches, [{ spaceId: named.id, storeId: fx.storeA, storeName: `Store A ${tag}`, exact: true }]);
  assert.ok(p.outline && p.outline.outer.length === 4);
  assert.deepEqual(r.body.cost, { model: 'test-vision-1', credits: 0.5, usd: 0.004 });
  assert.ok(r.body.notes.some((n) => n.includes('no readable label')));

  // Nothing was written to the draft.
  const after2 = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  assert.equal(after2.body.map.draftVersion, before.body.map.draftVersion);
  assert.equal(after2.body.map.draft.buildings[0].levels[0].walls.length, 0);

  // Recorded with its cost; the key is in neither record.
  const conv = await query('SELECT TOP 1 * FROM map_conversions WHERE branch_id = @b ORDER BY id DESC', { b: { type: sql.Int, value: fx.branchA } });
  assert.equal(conv.recordset[0].used_ai, true);
  assert.equal(conv.recordset[0].model, 'test-vision-1');
  assert.equal(Number(conv.recordset[0].credits), 0.5);
  const audit = await query(`SELECT TOP 1 details FROM audit_log WHERE action = 'map_converted' AND actor_email = @e ORDER BY id DESC`, { e: `mall_admin.${tag}@test.local` });
  const details = JSON.parse(audit.recordset[0].details);
  assert.equal(details.credits, 0.5);
  assert.ok(!audit.recordset[0].details.includes(KEY));
});

test('reading a boxed part maps the answer into that part of the plan', async () => {
  seen.length = 0;
  // One wall across the middle of the box, edge to edge.
  reply = () => chatAnswer(JSON.stringify({ isFloorPlan: true, outline: [], walls: [{ x1: 0, y1: 500, x2: 1000, y2: 500, kind: 'solid', sure: true }], doors: [], rooms: [], notes: '' }));
  const r = await convert({ levelId, crop: [0.5, 0, 1, 1] });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const [w] = r.body.proposal.walls;
  assert.ok(Math.abs(w.a[0] - 10) < 0.02 && Math.abs(w.b[0] - 20) < 0.02, `x ${w.a[0]} → ${w.b[0]}`);
  assert.ok(Math.abs(w.a[1] - 7) < 0.02);
  assert.deepEqual(r.body.proposal.crop, [0.5, 0, 1, 1]);
  const png = PNG.sync.read(Buffer.from(seen[0].body.messages[1].content[1].image_url.url.split(',')[1], 'base64'));
  assert.equal(png.width, 1000, 'only the boxed half is sent');
  assert.match(seen[0].body.messages[1].content[0].text, /is a part of/);
});

test('an unreadable answer is retried once, then refused; both paid calls are recorded', async () => {
  seen.length = 0;
  reply = () => chatAnswer('Sorry, here is a description of the plan instead.');
  const r = await convert();
  assert.equal(r.status, 502);
  assert.match(r.body.error, /could not be read/);
  assert.equal(seen.length, 2);
  const conv = await query('SELECT TOP 1 * FROM map_conversions WHERE branch_id = @b ORDER BY id DESC', { b: { type: sql.Int, value: fx.branchA } });
  assert.equal(Number(conv.recordset[0].credits), 1);
  assert.equal(conv.recordset[0].wall_count, 0);
});

test('"not a floor plan" and an answer cut short get clear messages', async () => {
  reply = () => chatAnswer(JSON.stringify({ isFloorPlan: false, outline: [], walls: [], doors: [], rooms: [], notes: 'This is a photo of a cat.' }));
  const no = await convert();
  assert.equal(no.status, 422);
  assert.match(no.body.error, /not a floor plan\. This is a photo of a cat\./);

  reply = () => {
    const a = chatAnswer('{"isFloorPlan": true, "walls": [');
    a.body.choices[0].finish_reason = 'length';
    return a;
  };
  const long = await convert();
  assert.equal(long.status, 422);
  assert.match(long.body.error, /section by section/);
});

// Corrected 2026-10-22 from a real reading: the gateway answers 500 both when no
// provider key is set up AND when the provider refuses the request (Gemini:
// "Request contains an invalid argument."), so its own words decide the message.
test('gateway errors become clear messages', async () => {
  for (const [status, said, expect, pattern] of [
    [402, 'out of credits', 402, /credits are used up/],
    [401, 'bad key', 502, /refused the platform key/],
    [500, 'No upstream key configured for provider gemini', 502, /no provider set up/],
    [500, 'Request contains an invalid argument.', 502, /could not take this reading.*no credits were used/],
    [502, 'upstream timeout', 502, /failed or timed out/],
  ]) {
    reply = () => ({ status, body: { error: { message: said } } });
    const r = await convert();
    assert.equal(r.status, expect, `gateway ${status} ${said}`);
    assert.match(r.body.error, pattern);
    assert.ok(!JSON.stringify(r.body).includes(KEY));
  }
});

test('a refused answer format falls back to a simpler one (relaxed schema, then plain JSON)', async () => {
  seen.length = 0;
  // The provider refuses any JSON schema (as Gemini did) but takes plain JSON.
  reply = (e) =>
    e.body?.response_format?.type === 'json_schema'
      ? { status: 500, body: { error: { message: 'Request contains an invalid argument.' } } }
      : chatAnswer(JSON.stringify(planAnswer()));
  const r = await convert();
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const formats = seen.filter((x) => x.url === '/v1/chat/completions').map((x) => x.body.response_format);
  assert.equal(formats.length, 2, 'test-vision-1 is not an OpenAI model: relaxed schema first, then plain JSON');
  assert.equal(formats[0].type, 'json_schema');
  assert.ok(!JSON.stringify(formats[0]).includes('additionalProperties'), 'the relaxed schema has no additionalProperties');
  assert.equal(formats[0].json_schema.strict, undefined);
  assert.deepEqual(formats[1], { type: 'json_object' });
});

test('only mall admins (and superadmins) read plans; owners cannot', async () => {
  reply = () => chatAnswer(JSON.stringify(planAnswer()));
  const owner = await call('POST', `/maps/${fx.branchA}/backdrops/${uploadKey}/convert`, { token: tokens.supervisor, body: { levelId } });
  assert.equal(owner.status, 403);
  const sa = await call('POST', `/maps/${fx.branchA}/backdrops/${uploadKey}/convert`, { token: tokens.superadmin, body: { levelId } });
  assert.equal(sa.status, 200, JSON.stringify(sa.body));
});

test('no platform daily cap any more: only the gateway wallet limits reading', async () => {
  const s = await call('GET', '/settings', { token: tokens.superadmin });
  assert.equal(s.body.rules.ai_daily_cap, undefined, 'the cap is no longer a setting');
  const cap = await call('PUT', '/settings', { token: tokens.superadmin, body: { ai_daily_cap: 1 } });
  assert.equal(cap.status, 400);
});

test('without a chosen model, or without a key, reading is refused with a clear message', async () => {
  await settings.setMany({ ai_model: '' }, fx.superadminId);
  const noModel = await convert();
  assert.equal(noModel.status, 409);
  assert.match(noModel.body.error, /chooses it in Settings/);

  config.ai.key = '';
  try {
    const noKey = await convert();
    assert.equal(noKey.status, 503);
    assert.match(noKey.body.error, /not set up/);
    const status = await call('GET', '/ai/status', { token: tokens.mall_admin });
    assert.equal(status.body.configured, false);
    assert.equal(status.body.quota, null);
    assert.equal((await call('GET', '/ai/models', { token: tokens.superadmin })).status, 503);
  } finally {
    config.ai.key = KEY;
  }
});

test("Round 19: each paid reading came off the mall admin's credits, linked to its record", async () => {
  const r = await query(
    `SELECT l.delta, l.conversion_id, mc.credits FROM ai_credit_ledger l JOIN map_conversions mc ON mc.id = l.conversion_id
      WHERE l.user_id = @u AND l.kind = 'reading'`,
    { u: { type: sql.Int, value: fx.mallAdminId } },
  );
  assert.ok(r.recordset.length > 0, 'readings were charged');
  for (const x of r.recordset) assert.equal(Number(x.delta), -Number(x.credits));
  const left = await query(`SELECT balance FROM ai_credit_balances WHERE user_id = @u`, { u: { type: sql.Int, value: fx.mallAdminId } });
  const spent = r.recordset.reduce((a, x) => a + Number(x.credits), 0);
  assert.equal(Math.round(Number(left.recordset[0].balance) * 10000), Math.round((100 - spent) * 10000));
});
