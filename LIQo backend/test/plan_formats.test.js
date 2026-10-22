// Round 16: plans may also be SVG, DXF or DWG (owner decisions 2026-10-22).
// Vector plans are drawn into a PNG; DXF/DWG get an exact scale from their unit;
// reading lays the AI's walls on the drawing's exact lines. A fake gateway and a
// fake ODA converter stand in for the real ones: no credits, no extra software.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { startServer, stopServer, api, makeFixtures, cleanFixtures, PASSWORD } from './helpers.js';
import { config } from '../src/config.js';
import * as settings from '../src/repos/settings.js';
import { readDxf, looksLikeDxf, plainMText } from '../src/maps/vector/dxf.js';
import { readSvg, looksLikeSvg, parseTransform } from '../src/maps/vector/svg.js';
import { looksLikeDwg } from '../src/maps/vector/dwg.js';
import { layoutFor, renderVector } from '../src/maps/vector/render.js';
import { apply } from '../src/maps/vector/common.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const UPLOADS = path.resolve(HERE, '../uploads/backdrops');

// ---- fixtures ----

/** A small ASCII DXF. Entities are [type, layer, ...group code pairs]. */
function dxf({ units = 4, entities = [], blocks = [] } = {}) {
  const out = ['0', 'SECTION', '2', 'HEADER'];
  if (units != null) out.push('9', '$INSUNITS', '70', String(units));
  out.push('0', 'ENDSEC', '0', 'SECTION', '2', 'BLOCKS');
  for (const b of blocks) {
    out.push('0', 'BLOCK', '8', '0', '2', b.name, '70', '0', '10', '0', '20', '0', '30', '0');
    for (const e of b.entities) out.push(...e);
    out.push('0', 'ENDBLK');
  }
  out.push('0', 'ENDSEC', '0', 'SECTION', '2', 'ENTITIES');
  for (const e of entities) out.push(...e);
  out.push('0', 'ENDSEC', '0', 'EOF');
  return Buffer.from(out.join('\n'));
}
const LINE = (layer, x1, y1, x2, y2) => ['0', 'LINE', '8', layer, '10', String(x1), '20', String(y1), '30', '0', '11', String(x2), '21', String(y2), '31', '0'];
const TEXT = (layer, x, y, s) => ['0', 'TEXT', '8', layer, '10', String(x), '20', String(y), '30', '0', '40', '250', '1', s];

// A 16 × 10 m slice of a mall in millimetres: one thick wall (two faces, 200 mm
// apart), a partition, a furniture line beside the wall, and a shop name.
const PLAN_DXF = dxf({
  entities: [
    LINE('A-WALL', 2000, 2000, 18000, 2000),
    LINE('A-WALL', 2000, 2200, 18000, 2200),
    LINE('A-WALL', 10000, 2200, 10000, 12000),
    LINE('FURN', 3000, 2350, 8000, 2350),
    TEXT('A-TEXT', 5000, 7000, 'STARBUCKS COFFEE'),
  ],
});

const SVG = Buffer.from(`<?xml version="1.0"?>
<!DOCTYPE svg [<!ENTITY boom "boom">]>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300">
  <script>alert('never runs')</script>
  <g id="Walls" transform="translate(10 20) scale(2)">
    <rect x="0" y="0" width="100" height="50"/>
    <path d="M 0 25 L 100 25"/>
  </g>
  <text x="60" y="80">Shop <tspan>A</tspan></text>
</svg>`);

// ---- server, fake gateway, fake ODA ----

let server;
let base;
let call;
let fx;
const tokens = {};
let saved;
let previousModel;
const keys = [];
const seen = [];
let reply = () => ({ status: 404, body: {} });
let gatewayServer;
let tmp;

before(async () => {
  gatewayServer = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const e = { url: req.url, body: body ? JSON.parse(body) : null };
      seen.push(e);
      const out = reply(e);
      res.writeHead(out.status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(out.body));
    });
  });
  await new Promise((r) => gatewayServer.listen(0, '127.0.0.1', r));
  saved = { ai: { ...config.ai }, oda: { ...config.oda } };
  config.ai.key = 'gws_test_only';
  config.ai.url = `http://127.0.0.1:${gatewayServer.address().port}/v1`;

  // The fake ODA converter copies a known DXF into the output folder.
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'liqo-r16-'));
  fs.writeFileSync(path.join(tmp, 'plan.dxf'), PLAN_DXF);
  fs.writeFileSync(
    path.join(tmp, 'fake-oda.mjs'),
    `import fs from 'node:fs'; import path from 'node:path';
const [, , inDir, outDir] = process.argv;
if (!fs.readdirSync(inDir).some((f) => f.endsWith('.dwg'))) process.exit(2);
fs.copyFileSync(${JSON.stringify(path.join(tmp, 'plan.dxf'))}, path.join(outDir, 'plan.dxf'));`,
  );

  const s = await startServer();
  server = s.server;
  base = s.base;
  call = api(base);
  const tag = `pf${Date.now().toString(36)}`;
  fx = await makeFixtures(tag);
  fx.tag = tag;
  for (const role of ['superadmin', 'mall_admin']) {
    const r = await call('POST', '/auth/login', { body: { email: `${role}.${tag}@test.local`, password: PASSWORD } });
    tokens[role] = r.body.token;
  }
  previousModel = await settings.getText('ai_model');
  await settings.setMany({ ai_model: 'test-vision-1' }, fx.superadminId);
  const created = await call('POST', `/maps/${fx.branchA}`, { token: tokens.mall_admin, body: { buildingName: 'Main', levelName: 'Ground', width: 40, depth: 30 } });
  assert.equal(created.status, 201);
  assert.equal((await call('POST', `/maps/${fx.branchA}/lock`, { token: tokens.mall_admin })).status, 200);
});

after(async () => {
  await settings.setMany({ ai_model: previousModel ?? '' }, fx?.superadminId ?? 0);
  config.ai.key = saved.ai.key;
  config.ai.url = saved.ai.url;
  config.oda.converter = saved.oda.converter;
  for (const k of keys) for (const ext of ['png', 'jpg', 'dxf', 'dwg', 'svg', 'vector.json']) fs.rmSync(path.join(UPLOADS, `${k}.${ext}`), { force: true });
  fs.rmSync(tmp, { recursive: true, force: true });
  await cleanFixtures(fx.tag);
  await stopServer(server);
  await new Promise((r) => gatewayServer.close(r));
});

async function upload(buf, name) {
  const form = new FormData();
  form.append('file', new Blob([buf]), name);
  const res = await fetch(`${base}/maps/${fx.branchA}/backdrops`, { method: 'POST', headers: { Authorization: `Bearer ${tokens.mall_admin}` }, body: form });
  const body = await res.json();
  if (body.backdrop) keys.push(body.backdrop.id);
  return { status: res.status, body };
}

// ---- readers ----

test('DXF: lines, blocks, curves and texts; y turned to point down; the unit read', () => {
  const buf = dxf({
    units: 4,
    blocks: [{ name: 'DOORBLK', entities: [LINE('0', 0, 0, 900, 0)] }],
    entities: [
      LINE('A-WALL', 0, 0, 5000, 0),
      ['0', 'INSERT', '8', 'A-DOOR', '2', 'DOORBLK', '10', '1000', '20', '2000', '30', '0', '41', '1', '42', '1', '50', '90'],
      ['0', 'ARC', '8', 'X', '10', '0', '20', '0', '30', '0', '40', '1000', '50', '0', '51', '90'],
      ['0', 'MTEXT', '8', 'A-TEXT', '10', '300', '20', '400', '30', '0', '40', '250', '1', '{\\fArial|b0;Unit 12\\PFood}'],
    ],
  });
  assert.ok(looksLikeDxf(buf));
  const v = readDxf(buf);
  assert.equal(v.units, 'mm');
  assert.equal(v.unitToM, 0.001);
  assert.deepEqual(v.layers.find((l) => l.name === 'A-WALL'), { name: 'A-WALL', lines: 1 });
  // The block's line, turned 90° at (1000, 2000), runs up to (1000, 2900): y down → -2000 … -2900.
  const doorLayer = v.layers.findIndex((l) => l.name === 'A-DOOR');
  const s = v.segments;
  const door = [];
  for (let i = 0; i < s.length; i += 5) if (s[i + 4] === doorLayer) door.push([s[i], s[i + 1], s[i + 2], s[i + 3]].map((n) => Math.round(n)));
  assert.deepEqual(door, [[1000, -2000, 1000, -2900]], 'block lines take the insert layer, rotation and place');
  assert.ok(v.layers.find((l) => l.name === 'X').lines >= 4, 'the arc becomes short pieces');
  assert.equal(v.texts[0].text, 'Unit 12 Food');
  assert.equal(plainMText('\\A1;{\\C1;Zara}'), 'Zara');
});

test('DXF without a unit, binary DXF and junk', () => {
  assert.equal(readDxf(dxf({ units: null, entities: [LINE('W', 0, 0, 10, 0)] })).units, null);
  assert.throws(() => readDxf(Buffer.from('AutoCAD Binary DXF\r\n\u001a\u0000rest', 'latin1')), /Binary DXF/);
  assert.throws(() => readDxf(dxf({ entities: [] })), /No lines/);
  assert.equal(looksLikeDxf(Buffer.from('hello')), false);
  assert.ok(looksLikeDwg(Buffer.from('AC1032\u0000\u0000rest', 'latin1')));
});

test('SVG: group transforms, paths and text; scripts and entities are ignored', () => {
  assert.ok(looksLikeSvg(SVG));
  const v = readSvg(SVG);
  assert.equal(v.units, null);
  // The rect (0..100 × 0..50) through translate(10 20) scale(2) spans 10..210 × 20..120.
  assert.deepEqual([v.bounds.minX, v.bounds.minY, v.bounds.maxX, v.bounds.maxY], [10, 20, 210, 120]);
  assert.deepEqual(v.layers.find((l) => l.name === 'Walls'), { name: 'Walls', lines: 5 });
  assert.equal(v.texts[0].text, 'Shop A');
  assert.ok(!JSON.stringify(v).includes('never runs'));
  assert.deepEqual(apply(parseTransform('rotate(90 10 10)'), 20, 10).map((n) => Math.round(n)), [10, 20]);
});

test('drawing: 50 px per metre when the unit is known, within the size limits', () => {
  const v = readDxf(PLAN_DXF);
  const L = layoutFor(v);
  assert.equal(L.k, 0.05, '50 px per metre = 0.05 px per millimetre');
  assert.equal(L.width, 840);
  assert.equal(L.height, 540);
  const png = PNG.sync.read(renderVector(v, L));
  assert.equal(png.width, 840);
  // The wall face at y = 2000 mm lands on picture row (12000 − 2000) × 0.05 + 20 = 520.
  assert.ok(png.data[(520 * 840 + 400) * 4] < 100, 'a dark line on row 520');
  assert.equal(png.data[(300 * 840 + 100) * 4], 255, 'white paper elsewhere');
  const huge = layoutFor({ bounds: { minX: 0, minY: 0, maxX: 1e6, maxY: 5e5 }, unitToM: 0.001 });
  assert.ok(Math.max(huge.width, huge.height) <= 6000);
});

// ---- upload routes ----

test('upload a DXF in mm: drawn as a PNG with an exact scale; the drawing is kept', async () => {
  const r = await upload(PLAN_DXF, 'level-1.dxf');
  assert.equal(r.status, 201, JSON.stringify(r.body));
  const b = r.body.backdrop;
  assert.equal(b.kind, 'dxf');
  assert.equal(b.units, 'mm');
  assert.ok(Math.abs(b.mpp - 0.02) < 1e-9, `mpp ${b.mpp}`);
  assert.equal(b.needsUnit, false);
  assert.equal(b.mimeType, 'image/png');
  assert.ok(fs.existsSync(path.join(UPLOADS, `${b.id}.dxf`)));
  assert.ok(fs.existsSync(path.join(UPLOADS, `${b.id}.vector.json`)));
  const pic = await fetch(`${base}/maps/${fx.branchA}/backdrops/${b.id}`, { headers: { Authorization: `Bearer ${tokens.mall_admin}` } });
  assert.equal(pic.headers.get('content-type'), 'image/png');
});

test('a DXF without a unit asks for one; the admin picks it and the scale follows', async () => {
  const r = await upload(dxf({ units: null, entities: [LINE('W', 0, 0, 20000, 0), LINE('W', 0, 0, 0, 10000)] }), 'nounit.dxf');
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.backdrop.needsUnit, true);
  assert.equal(r.body.backdrop.mpp, null);
  const key = r.body.backdrop.id;
  const set = await call('PUT', `/maps/${fx.branchA}/backdrops/${key}/unit`, { token: tokens.mall_admin, body: { unit: 'mm' } });
  assert.equal(set.status, 200, JSON.stringify(set.body));
  assert.equal(set.body.backdrop.units, 'mm');
  assert.equal(set.body.backdrop.needsUnit, false);
  // Unknown unit: drawn 4000 px across the 20 000 units, so 1 mm = 0.2 px → 5 mm per pixel.
  assert.ok(Math.abs(set.body.backdrop.mpp - 0.005) < 1e-9, `mpp ${set.body.backdrop.mpp}`);
  assert.equal((await call('PUT', `/maps/${fx.branchA}/backdrops/${key}/unit`, { token: tokens.mall_admin, body: { unit: 'parsec' } })).status, 400);
});

test('upload an SVG: drawn as a PNG, never served back as SVG, calibrated by hand', async () => {
  const r = await upload(SVG, 'plan.svg');
  assert.equal(r.status, 201, JSON.stringify(r.body));
  assert.equal(r.body.backdrop.kind, 'svg');
  assert.equal(r.body.backdrop.mpp, null);
  assert.equal(r.body.backdrop.needsUnit, false, 'SVG keeps the two-click calibration');
  const pic = await fetch(`${base}/maps/${fx.branchA}/backdrops/${r.body.backdrop.id}`, { headers: { Authorization: `Bearer ${tokens.mall_admin}` } });
  assert.equal(pic.headers.get('content-type'), 'image/png');
  const bytes = Buffer.from(await pic.arrayBuffer());
  assert.ok(!bytes.toString('latin1').includes('never runs'));
  const unit = await call('PUT', `/maps/${fx.branchA}/backdrops/${r.body.backdrop.id}/unit`, { token: tokens.mall_admin, body: { unit: 'mm' } });
  assert.equal(unit.status, 400);
});

test('DWG: refused clearly without the converter; read through ODA when it is set', async () => {
  const dwg = Buffer.concat([Buffer.from('AC1032', 'latin1'), Buffer.alloc(200)]);
  config.oda.converter = '';
  const no = await upload(dwg, 'level.dwg');
  assert.equal(no.status, 400);
  assert.match(no.body.error, /DWG support is not installed/);

  config.oda.converter = path.join(tmp, 'fake-oda.mjs');
  const yes = await upload(dwg, 'level.dwg');
  assert.equal(yes.status, 201, JSON.stringify(yes.body));
  assert.equal(yes.body.backdrop.kind, 'dwg');
  assert.equal(yes.body.backdrop.units, 'mm');
  assert.ok(fs.existsSync(path.join(UPLOADS, `${yes.body.backdrop.id}.dwg`)));
});

test('other files are refused by their content, whatever their name', async () => {
  const r = await upload(Buffer.from('%PDF-1.7 not a plan'), 'plan.png');
  assert.equal(r.status, 400);
  assert.match(r.body.error, /not accepted/);
});

test('deleting a vector plan removes the drawing and its lines too', async () => {
  const r = await upload(PLAN_DXF, 'temp.dxf');
  const key = r.body.backdrop.id;
  assert.equal((await call('DELETE', `/maps/${fx.branchA}/backdrops/${key}`, { token: tokens.mall_admin })).status, 204);
  for (const ext of ['png', 'dxf', 'vector.json']) assert.equal(fs.existsSync(path.join(UPLOADS, `${key}.${ext}`)), false, ext);
});

// ---- reading a CAD plan ----

test('reading a DXF: layers and texts go to the AI; its walls land on the exact CAD lines', async () => {
  const up = await upload(PLAN_DXF, 'read.dxf');
  const b = up.body.backdrop;
  // Place it so level metres = picture metres (centre of the 16.8 × 10.8 m picture).
  const bundle = await call('GET', `/maps/${fx.branchA}`, { token: tokens.mall_admin });
  const layout = bundle.body.map.draft;
  const level = layout.buildings[0].levels[0];
  level.outline = null;
  level.backdrop = { id: b.id, cx: (b.width * b.mpp) / 2, cz: (b.height * b.mpp) / 2, mpp: b.mpp, rot: 0, opacity: 0.5, locked: false };
  const put = await call('PUT', `/maps/${fx.branchA}/draft`, { token: tokens.mall_admin, body: { layout, baseVersion: bundle.body.map.draftVersion } });
  assert.equal(put.status, 200, JSON.stringify(put.body));

  // Picture metres: x = (x_mm − 2000)/1000 + 0.4, y = (12000 − y_mm)/1000 + 0.4.
  // The wall's faces sit at y = 10.4 and 10.2; the partition at x = 8.4.
  const W = b.width * b.mpp;
  const H = b.height * b.mpp;
  const u = (x, y) => ({ x: (x / W) * 1000, y: (y / H) * 1000 });
  const answer = {
    isFloorPlan: true,
    outline: [],
    // The AI's wall is roughly right (a little off and short); the partition is not reported.
    walls: [{ x1: u(0.6, 10.25).x, y1: u(0.6, 10.25).y, x2: u(16.2, 10.36).x, y2: u(16.2, 10.36).y, kind: 'solid', sure: false }],
    doors: [],
    rooms: [{ name: 'Starbucks', type: 'food', polygon: [u(0.4, 0.4), u(8.4, 0.4), u(8.4, 10.2), u(0.4, 10.2)], sure: true }],
    notes: '',
    wallLayers: ['A-WALL'],
  };
  seen.length = 0;
  reply = (e) => (e.url === '/v1/chat/completions' ? { status: 200, body: { model: 'test-vision-1', choices: [{ message: { content: JSON.stringify(answer) }, finish_reason: 'stop' }], x_gateway: { credits: 1, usd: 0.01 } } } : { status: 404, body: {} });

  const r = await call('POST', `/maps/${fx.branchA}/backdrops/${b.id}/convert`, { token: tokens.mall_admin, body: { levelId: level.id } });
  assert.equal(r.status, 200, JSON.stringify(r.body));

  const prompt = seen[0].body.messages[1].content[0].text;
  assert.match(prompt, /comes from a CAD drawing/);
  assert.match(prompt, /A-WALL: 3/);
  assert.match(prompt, /STARBUCKS COFFEE/);
  assert.ok(seen[0].body.response_format.json_schema.schema.required.includes('wallLayers'));

  const walls = r.body.proposal.walls;
  const wall = walls.find((w) => Math.abs(w.a[1] - w.b[1]) < 0.001);
  assert.ok(wall, 'the AI wall is there, straight');
  assert.ok(Math.abs(wall.a[1] - 10.3) < 0.002, `centre between the faces: ${wall.a[1]}`);
  assert.ok(Math.abs(wall.t - 0.2) < 0.002, `thickness from the faces: ${wall.t}`);
  assert.ok(Math.abs(Math.min(wall.a[0], wall.b[0]) - 0.4) < 0.01 && Math.abs(Math.max(wall.a[0], wall.b[0]) - 16.4) < 0.01, 'its ends come from the drawing');
  assert.ok(!r.body.proposal.uncertain.includes(wall.id), 'a wall confirmed by the drawing is sure');

  const partition = walls.find((w) => Math.abs(w.a[0] - 8.4) < 0.01 && Math.abs(w.b[0] - 8.4) < 0.01);
  assert.ok(partition, 'the partition the AI missed is taken from its wall layer');
  assert.equal(partition.kind, 'partition');
  assert.equal(walls.length, 2, 'the furniture line beside the wall is not a wall');
  assert.equal(r.body.stats.exactWalls, 2);

  assert.equal(r.body.proposal.spaces[0].name, 'STARBUCKS COFFEE', "the drawing's own spelling wins");
});
