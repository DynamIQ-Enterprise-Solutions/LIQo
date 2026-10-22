// Round 18: measured walls and rooms shaped by the walls (owner decision
// 2026-10-22: "measured walls + AI names"). No server, no AI.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { drawnPlan } from './plan_fixtures.js';
import { decodeImage } from '../src/maps/image.js';
import { measurePlan, roomsFromWalls, nameRooms, tidyRing } from '../src/maps/measure.js';
import { scaleFromDimension } from '../src/ai/floorplan.js';

test('walls are measured from the double lines; the door gap is found; a desk is not a wall', () => {
  const img = decodeImage(drawnPlan(), 'image/png');
  const m = measurePlan(img, { cx: 10, cz: 7, mpp: 0.01, rot: 0 });
  assert.equal(m.enough, true);
  assert.ok(m.walls.length >= 5 && m.walls.length <= 7, `walls ${m.walls.length}`);
  assert.equal(m.stats.doors, 1);
  const xs = m.walls.flatMap((w) => [w.a[0], w.b[0]]);
  assert.ok(Math.abs(Math.min(...xs) - 2.075) < 0.1 && Math.abs(Math.max(...xs) - 18.075) < 0.1);
  for (const w of m.walls) assert.ok(w.t > 0.1 && w.t < 0.25, `thickness ${w.t}`);
  // Nothing near the desk (4–5.5 m, 5–5.6 m).
  assert.ok(!m.walls.some((w) => Math.abs(w.a[1] - 5.3) < 0.4 && w.a[0] > 3.5 && w.b[0] < 6), 'the desk is not a wall');
});

test('a blank picture measures nothing', () => {
  const png = new PNG({ width: 400, height: 300 });
  png.data.fill(255);
  const m = measurePlan(decodeImage(PNG.sync.write(png), 'image/png'), { cx: 0, cz: 0, mpp: 0.01, rot: 0 });
  assert.equal(m.walls.length, 0);
  assert.equal(m.enough, false);
});

test('rooms fill the areas the walls enclose; the outline is the outer edge', () => {
  const walls = [
    { a: [2, 2], b: [18, 2], t: 0.2 },
    { a: [18, 2], b: [18, 12], t: 0.2 },
    { a: [2, 12], b: [18, 12], t: 0.2 },
    { a: [2, 2], b: [2, 12], t: 0.2 },
    { a: [10, 2], b: [10, 12], t: 0.1 },
    // A wall stopping 40 cm short of the far wall still closes its room.
    { a: [14, 2], b: [14, 11.6], t: 0.1 },
  ];
  const r = roomsFromWalls(walls);
  assert.equal(r.rooms.length, 3);
  const areas = r.rooms.map((x) => x.cells.length * 0.01).sort((a, b) => a - b);
  assert.ok(Math.abs(areas[0] - 36) < 3 && Math.abs(areas[2] - 76) < 4, `areas ${areas}`);
  assert.equal(r.outline.length, 4, 'a clean rectangle');
  const xs = r.outline.map((p) => p[0]);
  assert.ok(Math.abs(Math.min(...xs) - 1.9) < 0.15 && Math.abs(Math.max(...xs) - 18.1) < 0.15);
});

test("rooms take the AI's names by where its rooms lie", () => {
  const walls = [
    { a: [0, 0], b: [10, 0], t: 0.2 },
    { a: [10, 0], b: [10, 6], t: 0.2 },
    { a: [0, 6], b: [10, 6], t: 0.2 },
    { a: [0, 0], b: [0, 6], t: 0.2 },
    { a: [5, 0], b: [5, 6], t: 0.1 },
  ];
  const filled = roomsFromWalls(walls);
  // The AI's rooms are rough (a little off), but each covers most of one room.
  const ai = [
    [[0.3, 0.4], [4.6, 0.2], [4.9, 5.5], [0.2, 5.8]],
    [[5.4, 0.3], [9.7, 0.1], [9.8, 5.9], [5.2, 5.6]],
  ];
  const pick = nameRooms(filled, ai);
  const left = filled.rooms.findIndex((r) => Math.max(...r.outer.map((p) => p[0])) < 5.1);
  const right = filled.rooms.findIndex((r) => Math.min(...r.outer.map((p) => p[0])) > 4.9);
  assert.equal(pick[left], 0);
  assert.equal(pick[right], 1);
});

test('rings lose points on straight lines and near-duplicates, never a true corner', () => {
  assert.deepEqual(tidyRing([[0, 0], [5, 0], [10, 0], [10, 5], [0, 5], [0, 0.1]], 0.3), [[0, 0], [10, 0], [10, 5], [0, 5]]);
});

test('the scale from a dimension the AI read', () => {
  const box = { x0: 0, y0: 0, w: 2000, h: 1400 };
  const image = { width: 2000, height: 1400 };
  // 16 000 mm across 1600 px → 1 cm per pixel.
  assert.equal(scaleFromDimension({ x1: 100, y1: 71, x2: 900, y2: 71, mm: 16000 }, box, image), 0.01);
  assert.equal(scaleFromDimension({ x1: 100, y1: 71, x2: 900, y2: 71, mm: 0 }, box, image), null, 'no dimension');
  assert.equal(scaleFromDimension({ x1: 100, y1: 71, x2: 104, y2: 71, mm: 16000 }, box, image), null, 'too short to trust');
  assert.equal(scaleFromDimension({ x1: 100, y1: 71, x2: 900, y2: 71, mm: 5e9 }, box, image), null, 'no plan is that big');
  assert.equal(scaleFromDimension(null, box, image), null);
});
