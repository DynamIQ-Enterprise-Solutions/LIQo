// Round 21 (P1-08): the shopper package builder and the publish gate
// (docs/shopper-package-format.md, corrections agreed with the mobile session
// 2026-10-23). Pure: no database. Routes are checked with a small Dijkstra that
// reads the package the way the phone does.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildShopperPackage, stampPackage } from '../src/maps/shopper/build.js';
import { validateLayout, publishable } from '../src/maps/validator.js';
import { shortOf } from '../src/maps/shopper/levels.js';
import { placer as webPlacer } from '../../LIQo web/web/map3d/model.js';
import { rect, shop, level, layoutOf, mallFloor, routes, fixtures } from './support/shopper_layouts.js';

const build = (layout, extra = {}) => buildShopperPackage({ layout, branchId: 12, branchName: 'North', mallName: 'LIQo Mall', ...extra });

const reaches = (pkg, from, placeId) => {
  const p = pkg.places.find((x) => x.id === placeId);
  const d = routes(pkg, from);
  return p.nodes.some((n) => d.has(n));
};

/** Graph invariants every package keeps (the phone relies on them). */
function invariants(pkg) {
  const ids = new Set(pkg.graph.nodes.map((n) => n.id));
  const keys = new Set(pkg.graph.nodes.map((n) => `${n.lv}|${n.x.toFixed(1)}|${n.y.toFixed(1)}`));
  assert.equal(keys.size, pkg.graph.nodes.length, 'no two nodes within 0.1 m on a level');
  const seen = new Set();
  for (const e of pkg.graph.edges) {
    assert.ok(ids.has(e.a) && ids.has(e.b), 'edges join existing nodes');
    assert.notEqual(e.a, e.b, 'no self-loops');
    const k = `${e.a}|${e.b}|${e.kind}|${e.through ?? ''}|${e.conn ?? ''}|${e.oneWay ? 1 : 0}`;
    assert.ok(!seen.has(k), 'no duplicate edges');
    seen.add(k);
    if (e.kind === 'hop') assert.equal(e.cost, null);
  }
  for (const p of pkg.places) for (const n of p.nodes) assert.ok(ids.has(n));
  for (const c of pkg.connectors) for (const s of c.stops) assert.equal(pkg.graph.nodes.find((n) => n.id === s.node).lv, s.lv);
  for (const x of pkg.exits) assert.ok(ids.has(x.node));
  assert.equal(pkg.levels.filter((l) => l.ground).length, 1);
}

test('two rows of shops on a corridor: doors, routes from the entrance, the exit outside, no stray enter edges', () => {
  const layout = layoutOf([mallFloor()]);
  const r = build(layout, { links: [{ spaceKey: 'sp-101', storeId: 345, storeName: 'Uniqlo' }], appCategories: { 345: 'fashion' } });
  assert.deepEqual(r.problems, []);
  const pkg = r.package;
  invariants(pkg);
  const exit = pkg.exits.find((x) => x.id === 'op-main');
  assert.ok(exit, 'an entrance on a boundary wall is an exit');
  assert.equal(exit.name, 'Main entrance');
  const outside = pkg.graph.nodes.find((n) => n.id === exit.node);
  assert.equal(outside.out, true);
  assert.ok(outside.x < 0, 'the exit node is outside the wall');
  const enters = pkg.graph.edges.filter((e) => e.kind === 'enter');
  assert.equal(enters.length, 1, 'only the indoor–outdoor door is an enter edge');
  assert.equal(enters[0].label, 'Main entrance');
  for (const id of ['sp-101', 'sp-102', 'sp-103', 'sp-104']) assert.ok(reaches(pkg, exit.node, id), id);
  const uniqlo = pkg.places.find((p) => p.id === 'sp-101');
  assert.equal(uniqlo.storeId, 345);
  assert.equal(uniqlo.cat, 'fashion');
  assert.equal(uniqlo.w, 1.2);
  // The corridor runs along its centre (z ≈ 10).
  const corridor = pkg.graph.nodes.filter((n) => n.x > 13 && n.x < 30 && !n.out);
  assert.ok(corridor.some((n) => Math.abs(n.y - 10) < 0.4), 'centre line of the corridor');
  // Route length from the entrance to Unit 102's door: about 18 m along the corridor plus the door spur.
  const d = routes(pkg, exit.node);
  const len = Math.min(...pkg.places.find((p) => p.id === 'sp-102').nodes.map((n) => d.get(n)));
  assert.ok(len > 17 && len < 26, `route length ${len}`);
});

test('a store with two doors gets a cut-through across its floor, by place id, at 1.25 × the distance', () => {
  const layout = layoutOf([mallFloor()]);
  const r = build(layout, { links: [{ spaceKey: 'sp-103', storeId: 9, storeName: 'Corner Store' }] });
  const through = r.package.graph.edges.filter((e) => e.through === 'sp-103');
  assert.ok(through.length >= 3, 'door to inside, inside to inside');
  const floor = through.find((e) => Math.abs(e.cost - 1.25 * e.len) < 1e-3 && e.len > 0);
  assert.ok(floor, 'the walk across the floor costs 1.25 × its length');
  const inner = r.package.graph.nodes.filter((n) => n.inner);
  assert.ok(inner.length >= 2);
  assert.equal(r.package.places.find((p) => p.id === 'sp-103').kind, 'box');
});

test('two levels: a three-stop lift both ways, a one-way escalator kept in its direction, a level with no way up is refused', () => {
  const floors = [0, 5, 10].map((e, k) =>
    level(`lv-${k}`, k === 0 ? 'Ground floor' : `Level ${k + 1}`, e, k === 0 ? [] : [shop(`sp-${k}`, `Shop ${k}`, [2, 0, 10, 6], ['s'])], {
      features: k === 0 ? [{ id: 'ft-in', type: 'entrance', x: 1, z: 15 }] : [],
    }),
  );
  const lift = { id: 'cn-lift', kind: 'elevator', name: 'West lifts', endpoints: [0, 1, 2].map((k) => ({ level: `lv-${k}`, x: 30, z: 15 })) };
  const esc = { id: 'cn-esc', kind: 'escalator', name: 'Down escalator', oneWay: true, endpoints: [{ level: 'lv-1', x: 20, z: 15 }, { level: 'lv-0', x: 20, z: 15 }] };
  const r = build(layoutOf(floors, [lift, esc]));
  assert.deepEqual(r.problems, []);
  const pkg = r.package;
  invariants(pkg);
  const hops = pkg.graph.edges.filter((e) => e.conn === 'cn-lift');
  assert.equal(hops.length, 2);
  assert.ok(hops.every((e) => !e.oneWay && e.ctype === 'lift' && e.kind === 'hop'));
  const down = pkg.graph.edges.filter((e) => e.conn === 'cn-esc');
  assert.equal(down.length, 1);
  assert.equal(down[0].oneWay, true);
  const nodeLv = new Map(pkg.graph.nodes.map((n) => [n.id, n.lv]));
  assert.deepEqual([nodeLv.get(down[0].a), nodeLv.get(down[0].b)], [1, 0], 'down: level 2 to ground');
  assert.deepEqual(pkg.connectors.find((c) => c.id === 'cn-esc').stops.map((s) => s.lv), [1, 0]);
  assert.deepEqual(pkg.connectors.find((c) => c.id === 'cn-lift').stops.map((s) => s.lv), [0, 1, 2]);
  // Without the lift, level 3 has no way up.
  const r2 = build(layoutOf(floors, [esc]));
  assert.ok(r2.problems.some((p) => p.code === 'level_unreachable' && p.message === "Level 3 can't be reached from an entrance: add stairs, an escalator or a lift that leads there"));
  // With only an up escalator, level 2 can be reached but there is no way back.
  const up = { ...esc, id: 'cn-up', endpoints: [{ level: 'lv-0', x: 20, z: 15 }, { level: 'lv-1', x: 20, z: 15 }] };
  const r3 = build(layoutOf(floors.slice(0, 2), [up]));
  assert.ok(r3.warnings.some((w) => w.code === 'no_way_back'));
});

test('a rotated building is drawn and routed in one branch frame, matching the 3D preview', () => {
  const plain = mallFloor();
  const turned = { ...structuredClone(plain), rot: 30, offset: [5, -3] };
  const layout = layoutOf([turned], [], { origin: [100, 50], rot: 90 });
  const r = build(layout);
  assert.deepEqual(r.problems, []);
  invariants(r.package);
  const place = webPlacer(layout.buildings[0], layout.buildings[0].levels[0]);
  const corner = place([0, 0]);
  const drawn = r.package.levels[0].outlines[0].outer[0];
  assert.ok(Math.abs(drawn[0] - corner[0]) < 0.01 && Math.abs(drawn[1] - corner[1]) < 0.01);
  const straight = build(layoutOf([plain]));
  const lenOf = (pkg) => {
    const exit = pkg.exits.find((x) => x.id === 'op-main').node;
    const d = routes(pkg, exit);
    return Math.min(...pkg.places.find((p) => p.id === 'sp-104').nodes.map((n) => d.get(n)));
  };
  const a = lenOf(r.package);
  const b = lenOf(straight.package);
  assert.ok(Math.abs(a - b) / b < 0.05, `${a} vs ${b}`);
});

test('unreachable shops are refused in plain words, with the space id', () => {
  const closed = shop('sp-101', 'Unit 101', [2, 0, 12, 8], []);
  const back = shop('sp-back', 'Stock room', [14, 0, 24, 8], []);
  const front = shop('sp-front', 'Unit 103', [14, 12, 24, 20], ['n']);
  const lvl = level('lv-g', 'Ground floor', 0, [closed, back, front], { features: [{ id: 'ft-in', type: 'entrance', x: 1, z: 10 }] });
  const r = build(layoutOf([lvl]), { links: [{ spaceKey: 'sp-101', storeId: 345, storeName: 'Uniqlo' }] });
  const p = r.problems.find((x) => x.ids[0] === 'sp-101');
  assert.equal(p.message, "Uniqlo (Unit 101) can't be reached: it has no door to a corridor");
  assert.ok(r.problems.some((x) => x.ids[0] === 'sp-back' && x.message === "Stock room can't be reached: it has no door to a corridor"));
  assert.ok(!r.problems.some((x) => x.ids[0] === 'sp-front'));
});

test('a connector stop away from any walkway is refused; a level without corridor is refused', () => {
  const g = level('lv-g', 'Ground floor', 0, [shop('sp-big', 'Big Store', [5, 5, 35, 15], ['n'])], { features: [{ id: 'ft-in', type: 'entrance', x: 1, z: 2 }] });
  const two = level('lv-2', 'Level 2', 5, [], { outline: rect(0, 0, 40, 20) });
  const lift = { id: 'cn-l', kind: 'elevator', name: 'West lifts', endpoints: [{ level: 'lv-g', x: 20, z: 10 }, { level: 'lv-2', x: 20, z: 10 }] };
  const r = build(layoutOf([g, two], [lift]));
  assert.ok(r.problems.some((p) => p.code === 'stop_off_walkway' && p.message === "West lifts, Ground floor: the lift door isn't on a walkway" && p.ids[0] === 'cn-l'));
  const full = level('lv-g', 'Ground floor', 0, [], { outline: rect(0, 0, 10, 10), spaces: [{ id: 'sp-all', name: 'Everything', type: 'retail', shape: { outer: rect(0, 0, 10, 10), holes: [] } }], features: [{ id: 'ft-in', type: 'entrance', x: 5, z: 0 }] });
  const r2 = build(layoutOf([full]));
  assert.ok(r2.problems.some((p) => p.code === 'no_corridor' && p.message === 'Ground floor has no corridor'));
});

test('the same map always gives the same bytes, whatever the order of its arrays', () => {
  const layout = layoutOf([mallFloor()]);
  const a = stampPackage(build(layout).package, { version: 3, publishedAt: '2026-10-23T10:00:00+08:00' });
  const shuffled = structuredClone(layout);
  const lv = shuffled.buildings[0].levels[0];
  lv.spaces.reverse();
  lv.walls.reverse();
  lv.openings.reverse();
  const b = stampPackage(build(shuffled).package, { version: 3, publishedAt: '2026-10-23T10:00:00+08:00' });
  assert.equal(a.checksum, b.checksum);
  assert.match(a.checksum, /^[0-9a-f]{64}$/);
});

test('the maps the other tests publish pass the gate; packages carry the agreed envelope', () => {
  const fixture = level('lv-ground', 'Ground floor', 0, [], {
    outline: rect(0, 0, 40, 30),
    features: [{ id: 'ft-e', type: 'entrance', x: 1, z: 0 }],
    spaces: [{ id: 'sp-1', name: 'Unit 1', type: 'retail', shape: { outer: rect(1, 1, 5, 5), holes: [] } }],
  });
  const r = build(layoutOf([fixture]));
  assert.deepEqual(r.problems, []);
  const pkg = r.package;
  for (const k of ['formatVersion', 'branchId', 'branchName', 'mallName', 'version', 'publishedAt', 'units', 'levels', 'spaces', 'walls', 'openings', 'features', 'graph', 'places', 'connectors', 'exits', 'buildings', 'bounds']) assert.ok(k in pkg, k);
  assert.equal(pkg.formatVersion, 1);
  assert.equal(pkg.levels[0].short, 'G');
  assert.ok(Array.isArray(pkg.levels[0].outlines));
});

test('places saved on phones that a new version drops are a warning; a package over the limit is refused', () => {
  const layout = layoutOf([mallFloor()]);
  const previous = { places: [{ id: 'sp-101', storeId: 345, name: 'Uniqlo' }, { id: 'sp-gone', storeId: null, name: 'Old kiosk' }] };
  const r = build(layout, { links: [{ spaceKey: 'sp-101', storeId: 345, storeName: 'Uniqlo' }], previous });
  assert.deepEqual(r.warnings.find((w) => w.code === 'places_gone')?.message, '1 place shoppers may have saved will be gone: Old kiosk');
  const big = build(layout, { limits: { maxBytes: 1000 } });
  assert.ok(big.problems.some((p) => p.code === 'too_big'));
});

test('floor short labels', () => {
  assert.deepEqual(['Ground floor', 'Level 2', 'Basement 1', 'Lower ground', 'Third floor', 'Mezzanine'].map((n) => shortOf(n)), ['G', '2', 'B1', 'LG', '3', 'M']);
  assert.equal(shortOf('Upper ground (UG)', ['UG']), 'UG');
});

test('a large mall builds in time and stays well under the size limit', { timeout: 120000 }, () => {
  const parts = [];
  for (let row = 0; row < 6; row++) {
    for (let col = 0; col < 16; col++) {
      const x = 4 + col * 12;
      const z = 4 + row * 24;
      parts.push(shop(`sp-${row}-${col}`, `Unit ${row}${col}`, [x, z, x + 10, z + 8], ['s']));
    }
  }
  const floors = [0, 5].map((e, k) => level(`lv-${k}`, k ? 'Level 2' : 'Ground floor', e, k ? parts.map((p) => structuredClone(p)).map((p) => ({ ...p, space: { ...p.space, id: `${p.space.id}-u` }, walls: p.walls.map((w) => ({ ...w, id: `${w.id}-u` })), openings: p.openings.map((o) => ({ ...o, id: `${o.id}-u`, wall: `${o.wall}-u` })) })) : parts, { outline: rect(0, 0, 200, 150), features: k ? [] : [{ id: 'ft-in', type: 'entrance', x: 0.5, z: 75 }] }));
  const lift = { id: 'cn-l', kind: 'elevator', name: 'Lifts', endpoints: [{ level: 'lv-0', x: 100, z: 15 }, { level: 'lv-1', x: 100, z: 15 }] };
  const t0 = performance.now();
  const r = build(layoutOf(floors, [lift]));
  const ms = performance.now() - t0;
  assert.deepEqual(r.problems, []);
  invariants(r.package);
  assert.ok(ms < 30000, `${Math.round(ms)} ms`);
  assert.ok(r.stats.sizeBytes < 5 * 1024 * 1024, `${r.stats.sizeBytes} bytes`);
});

test('the published fixtures for the mobile loader test are up to date (run node tool/shopper-fixtures.mjs after a builder change)', async () => {
  const { staleFixtures } = await import('../tool/shopper-fixtures.mjs');
  assert.deepEqual(staleFixtures(), []);
});
