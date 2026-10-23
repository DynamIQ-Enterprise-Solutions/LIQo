// Round 18 through the real route (owner decisions 2026-10-22): measured walls
// + AI names, rooms shaped by the walls, and the scale found from a dimension
// when a plan was never calibrated. A fake gateway answers; no credits.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, giveTestCredits, PASSWORD } from './helpers.js';
import { drawnPlan } from './plan_fixtures.js';
import { config } from '../src/config.js';
import * as settings from '../src/repos/settings.js';
import { PLANS_DIR } from '../src/storage/files.js';

const UPLOADS = PLANS_DIR;
const tag = `am${Date.now().toString(36)}`;
let server, base, call, fx, token, saved, previousModel, key, levelId, gatewayServer;
let answer = null;
const seen = [];

// The drawn plan is 2000 × 1400 px; at 1 cm per pixel it is 20 × 14 m.
const ux = (m) => (m / 20) * 1000;
const uy = (m) => (m / 14) * 1000;

/** The AI's reading: walls a little off (as vision models are), a glass wall the pixels cannot see, names, and the dimension above the box. */
function aiAnswer() {
  return {
    isFloorPlan: true,
    outline: [{ x: ux(2), y: uy(2) }, { x: ux(18), y: uy(2) }, { x: ux(18), y: uy(12) }, { x: ux(2), y: uy(12) }],
    walls: [
      { x1: ux(2.3), y1: uy(2.25), x2: ux(17.8), y2: uy(2.3), kind: 'boundary', sure: true },
      { x1: ux(2.2), y1: uy(12.3), x2: ux(17.7), y2: uy(12.25), kind: 'boundary', sure: true },
      // The single-line glass wall at x = 14 m: only the AI sees it.
      { x1: ux(14), y1: uy(2.1), x2: ux(14), y2: uy(12.1), kind: 'glass', sure: true },
    ],
    doors: [],
    rooms: [
      { name: 'Office 1', type: 'office', polygon: [{ x: ux(2.5), y: uy(2.5) }, { x: ux(9.5), y: uy(2.4) }, { x: ux(9.6), y: uy(11.5) }, { x: ux(2.4), y: uy(11.6) }], sure: true },
      { name: 'Pantry', type: 'food', polygon: [{ x: ux(14.4), y: uy(2.6) }, { x: ux(17.6), y: uy(2.5) }, { x: ux(17.5), y: uy(11.4) }, { x: ux(14.3), y: uy(11.5) }], sure: true },
    ],
    notes: '',
    wallLayers: [],
    dimension: { x1: ux(2), y1: uy(1), x2: ux(18), y2: uy(1), mm: 16000 },
  };
}

before(async () => {
  gatewayServer = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      seen.push(body ? JSON.parse(body) : null);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ model: 'test-vision-1', choices: [{ message: { content: JSON.stringify(answer) }, finish_reason: 'stop' }], x_gateway: { creditsCharged: 0.3, costUSD: 0.01 } }));
    });
  });
  await new Promise((r) => gatewayServer.listen(0, '127.0.0.1', r));
  saved = { ...config.ai };
  config.ai.key = 'gws_test_only';
  config.ai.url = `http://127.0.0.1:${gatewayServer.address().port}/v1`;
  const s = await startServer();
  server = s.server;
  base = s.base;
  call = api(base);
  fx = await makeFixtures(tag);
  // Owner decision 2026-10-23 (Round 19): a mall admin reads plans only with AI credits.
  await giveTestCredits(fx.mallAdminId, 100);
  token = (await call('POST', '/auth/login', { body: { email: `mall_admin.${tag}@test.local`, password: PASSWORD } })).body.token;
  previousModel = await settings.getText('ai_model');
  await settings.setMany({ ai_model: 'test-vision-1' }, fx.superadminId);
  assert.equal((await call('POST', `/maps/${fx.branchA}`, { token, body: { outline: false } })).status, 201);
  assert.equal((await call('POST', `/maps/${fx.branchA}/lock`, { token })).status, 200);
  const form = new FormData();
  form.append('file', new Blob([drawnPlan()], { type: 'image/png' }), 'drawn.png');
  const up = await (await fetch(`${base}/maps/${fx.branchA}/backdrops`, { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form })).json();
  key = up.backdrop.id;
});

after(async () => {
  await settings.setMany({ ai_model: previousModel ?? '' }, fx?.superadminId ?? 0);
  Object.assign(config.ai, saved);
  for (const ext of ['png', 'jpg']) fs.rmSync(path.join(UPLOADS, `${key}.${ext}`), { force: true });
  await cleanFixtures(tag);
  await stopServer(server);
  await new Promise((r) => gatewayServer.close(r));
});

/** Places the plan with the given scale (and whether it was set on purpose), then reads it. */
async function read({ mpp, calibrated, cx = 10, cz = 7 }) {
  const bundle = await call('GET', `/maps/${fx.branchA}`, { token });
  const layout = bundle.body.map.draft;
  const level = layout.buildings[0].levels[0];
  levelId = level.id;
  level.backdrop = { id: key, cx, cz, mpp, rot: 0, opacity: 0.5, locked: false, calibrated };
  const put = await call('PUT', `/maps/${fx.branchA}/draft`, { token, body: { layout, baseVersion: bundle.body.map.draftVersion } });
  assert.equal(put.status, 200, JSON.stringify(put.body));
  answer = aiAnswer();
  seen.length = 0;
  return call('POST', `/maps/${fx.branchA}/backdrops/${key}/convert`, { token, body: { levelId } });
}

test('walls come from the pixels exactly; the AI adds the glass wall and the names; rooms fill between walls', async () => {
  const r = await read({ mpp: 0.01, calibrated: true });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const p = r.body.proposal;
  assert.ok(r.body.stats.measuredWalls >= 5, `measured ${r.body.stats.measuredWalls}`);

  // The top wall is where the drawing has it (2.075 m), not where the AI guessed (2.25 m).
  const top = p.walls.find((w) => Math.abs(w.a[1] - w.b[1]) < 0.01 && w.a[1] < 3);
  assert.ok(Math.abs(top.a[1] - 2.075) < 0.05, `top wall at ${top.a[1]}`);
  assert.equal(p.walls.filter((w) => Math.abs(w.a[1] - w.b[1]) < 0.01 && w.a[1] < 3).length, 1, 'the AI copy of the top wall is not added twice');
  assert.ok(p.walls.some((w) => w.kind === 'glass' && Math.abs(w.a[0] - 14) < 0.1), 'the glass wall only the AI saw');
  assert.equal(p.openings.length, 1, 'the measured door in the partition');

  // Three rooms between the walls: Office 1, the middle (unnamed, unsure), Pantry.
  assert.equal(p.spaces.length, 3, JSON.stringify(p.spaces.map((s) => s.name)));
  const office = p.spaces.find((s) => s.name === 'Office 1');
  const pantry = p.spaces.find((s) => s.name === 'Pantry');
  assert.ok(office && pantry);
  assert.equal(office.type, 'office');
  const ox = office.shape.outer.map((q) => q[0]);
  assert.ok(Math.min(...ox) > 2.05 && Math.max(...ox) < 10.1, 'Office 1 fills the space inside its walls');
  const middle = p.spaces.find((s) => !s.name);
  assert.ok(p.uncertain.includes(middle.id), 'a room the AI did not name is marked unsure');
  assert.ok(r.body.stats.roomsFromWalls >= 3);
  // The outline follows the outer faces of the walls.
  assert.equal(p.outline.outer.length, 4);
  assert.equal(r.body.scaleFound, null, 'a calibrated plan keeps its scale');
  assert.match(seen[0].messages[1].content[0].text, /20\.0 m wide/);
});

test('a plan never calibrated gets its scale from the dimension the AI read', async () => {
  // Stretched 5× too big (as a plan placed by "fit" is), and never calibrated.
  const r = await read({ mpp: 0.05, calibrated: false, cx: 50, cz: 35 });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.match(seen[0].messages[1].content[0].text, /real size is not known/);
  assert.deepEqual(r.body.scaleFound, { mpp: 0.01, mm: 16000 });
  // At the found scale the box is 16 m wide again (centred where the plan was).
  const xs = r.body.proposal.walls.flatMap((w) => [w.a[0], w.b[0]]);
  assert.ok(Math.abs(Math.max(...xs) - Math.min(...xs) - 16) < 0.2, `width ${Math.max(...xs) - Math.min(...xs)}`);
  assert.equal(r.body.proposal.spaces.length, 3);
});
