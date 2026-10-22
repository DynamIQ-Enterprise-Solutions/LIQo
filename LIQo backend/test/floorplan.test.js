// Round 15 pieces that need no server: the picture sent to the AI, reading its
// answer, the gateway's helper lists, and store-name matching.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { preparePicture, parseAnswer, nameSimilarity, matchStores, cropBox, toProposal } from '../src/ai/floorplan.js';
import { normaliseModels, normaliseQuota, readingModels, costOf, textOf } from '../src/ai/gateway.js';

function rgba(w, h) {
  const data = Buffer.alloc(w * h * 4, 255);
  return { width: w, height: h, data };
}

test('the picture is cut to the box, kept at most 2000 px, and carries the red grid', () => {
  const img = rgba(5000, 2500);
  const p = preparePicture(img, null);
  const png = PNG.sync.read(Buffer.from(p.url.split(',')[1], 'base64'));
  assert.equal(png.width, 2000);
  assert.equal(png.height, 1000);
  // A grid line at 1/20 across: reddish, not white.
  const x = Math.round(png.width / 20);
  const o = (500 * png.width + x) * 4;
  assert.ok(png.data[o] > 200 && png.data[o + 1] < 230, `grid pixel ${png.data.slice(o, o + 3).join(',')}`);

  const part = preparePicture(img, [0.25, 0.5, 0.75, 1]);
  assert.deepEqual(part.box, { x0: 1250, y0: 1250, w: 2500, h: 1250 });
  assert.deepEqual(cropBox(100, 100, [0.9, 0.9, 0.1, 0.1]), { x0: 10, y0: 10, w: 80, h: 80 }, 'a box drawn backwards still works');
});

test('thin ink lines survive shrinking', () => {
  const img = rgba(6000, 1000);
  for (let y = 0; y < 1000; y++) {
    const o = (y * 6000 + 3001) * 4;
    img.data[o] = img.data[o + 1] = img.data[o + 2] = 0; // a 1 px black line
  }
  const p = preparePicture(img, [0.4, 0, 0.6, 0.5]);
  const png = PNG.sync.read(Buffer.from(p.url.split(',')[1], 'base64'));
  let darkest = 255;
  for (let x = 0; x < png.width; x++) darkest = Math.min(darkest, png.data[(300 * png.width + x) * 4]);
  assert.ok(darkest < 160, `line still dark: ${darkest}`);
});

test('answers: fenced JSON, junk around it, and bad values are handled', () => {
  const a = parseAnswer('```json\n{"isFloorPlan":true,"outline":[],"walls":[{"x1":-5,"y1":"10","x2":2000,"y2":10,"kind":"brick","sure":true}],"doors":[],"rooms":[{"name":"Shop","type":"spaceship","polygon":[],"sure":"maybe"}],"notes":"ok"}\n```');
  assert.equal(a.walls[0].x1, 0, 'clamped into 0–1000');
  assert.equal(a.walls[0].y1, 10, 'numbers in quotes are read');
  assert.equal(a.walls[0].x2, 1000);
  assert.equal(a.walls[0].kind, 'solid', 'unknown kinds fall back');
  assert.equal(a.rooms[0].type, 'retail');
  assert.equal(a.rooms[0].sure, true);
  assert.ok(parseAnswer('Here you go: {"isFloorPlan":true,"outline":[],"walls":[],"doors":[],"rooms":[],"notes":""} Hope that helps'));
  assert.equal(parseAnswer('no json here'), null);
  assert.equal(parseAnswer('{"isFloorPlan": true, "walls": ['), null);
});

test('rotation: the calibration turns picture metres into level metres', () => {
  // A 1000 × 1000 px picture at 1 cm/px centred at (50, 50), turned 90°.
  const answer = { walls: [{ x1: 0, y1: 500, x2: 1000, y2: 500, kind: 'solid', sure: true }], doors: [], rooms: [], outline: [] };
  let n = 0;
  const p = toProposal(answer, { box: { x0: 0, y0: 0, w: 1000, h: 1000 }, image: { width: 1000, height: 1000 }, calib: { cx: 50, cz: 50, mpp: 0.01, rot: 90 }, newId: (pre) => `${pre}-${++n}` });
  const [w] = p.walls;
  // A horizontal line through the centre becomes vertical through (50, 50).
  assert.ok(Math.abs(w.a[0] - 50) < 1e-6 && Math.abs(w.b[0] - 50) < 1e-6);
  assert.deepEqual([Math.min(w.a[1], w.b[1]), Math.max(w.a[1], w.b[1])], [45, 55]);
});

test('gateway lists: the real formats (seen 2026-10-22)', () => {
  const list = normaliseModels({
    object: 'list',
    data: [
      { id: 'gpt-5.1', object: 'model', owned_by: 'openai', type: 'chat', label: 'GPT-5.1', available: true },
      { id: 'claude-sonnet-5', owned_by: 'anthropic', type: 'chat', label: 'Claude Sonnet 5', available: false },
      { id: 'gemini-3-pro-image', owned_by: 'gemini', type: 'image', label: 'Nano Banana Pro', available: true },
      { id: 'whisper-1', owned_by: 'openai', type: 'audio', label: 'Whisper', available: true },
      { id: 'gpt-5.1', owned_by: 'openai', type: 'chat', label: 'duplicate', available: true },
    ],
  });
  assert.equal(list.length, 4, 'duplicates are dropped');
  // Only chat models the gateway marks available can read a plan.
  assert.deepEqual(readingModels(list), [{ id: 'gpt-5.1', label: 'GPT-5.1', provider: 'openai' }]);

  assert.deepEqual(
    normaliseQuota({ enforced: true, blocked: true, reason: 'Out of AI credits. Contact your administrator to top up.', balance: 0, daily: { usedTokens: 0, limitTokens: 0, usedCredits: 0, limitCredits: 0 } }),
    { balance: 0, usedToday: 0, dailyCap: null, blocked: true, reason: 'Out of AI credits. Contact your administrator to top up.' },
    'a daily limit of 0 is no cap',
  );
  assert.deepEqual(normaliseQuota({ blocked: false, balance: '120.5', daily: { usedCredits: 3.5, limitCredits: 50 } }), { balance: 120.5, usedToday: 3.5, dailyCap: 50, blocked: false, reason: null });
  assert.deepEqual(normaliseQuota({}), { balance: null, usedToday: null, dailyCap: null, blocked: false, reason: null });
  assert.deepEqual(costOf({ x_gateway: { credits: '1.25', usd: 0.01 } }), { credits: 1.25, usd: 0.01 });
  // The gateway's real field names (seen 2026-10-22).
  assert.deepEqual(costOf({ x_gateway: { creditsCharged: 0.0639, costUSD: 0.0002235, tenant: 'x', provider: 'gemini' } }), { credits: 0.0639, usd: 0.0002235 });
  assert.deepEqual(costOf({}), { credits: 0, usd: 0 });
  assert.equal(textOf({ choices: [{ message: { content: [{ type: 'text', text: '{"a":' }, { type: 'text', text: '1}' }] } }] }), '{"a":1}');
});

test('store names: case, punctuation and small spelling slips are forgiven; strangers are not', () => {
  assert.equal(nameSimilarity('JOLLIBEE', 'Jollibee'), 1);
  assert.ok(nameSimilarity("McDonald's", 'Mcdonalds') >= 0.98);
  assert.ok(nameSimilarity('Jollibee', 'Jollibee Express') >= 0.8);
  assert.ok(nameSimilarity('Starbuks', 'Starbucks') >= 0.8);
  assert.ok(nameSimilarity('Uniqlo', 'Watsons') < 0.8);
  assert.equal(nameSimilarity('', 'Anything'), 0);
  const matches = matchStores(
    [{ id: 'a', name: 'STARBUCKS' }, { id: 'b', name: '' }, { id: 'c', name: 'Unit 12' }],
    [{ id: 1, name: 'Starbucks' }, { id: 2, name: 'Starbucks Reserve' }],
  );
  assert.deepEqual(matches, [{ spaceId: 'a', storeId: 1, storeName: 'Starbucks', exact: true }]);
});
