// Hand-made maps for the shopper package builder (Round 21, P1-08), shared by
// test/shopper_package.test.js and tool/shopper-fixtures.mjs (which writes
// the published fixtures the mobile session's loader test reads).
import assert from 'node:assert/strict';
import { validateLayout, publishable } from '../../src/maps/validator.js';

export const rect = (x0, z0, x1, z1) => [[x0, z0], [x1, z0], [x1, z1], [x0, z1]];

/** A shop with four walls and doors on the given sides ('n' = z0 side, 's', 'w', 'e'). */
export function shop(id, name, [x0, z0, x1, z1], doors = [], { t = 0.2, type = 'retail' } = {}) {
  const walls = [
    { id: `${id}-wn`, a: [x0, z0], b: [x1, z0], t, kind: 'solid' },
    { id: `${id}-we`, a: [x1, z0], b: [x1, z1], t, kind: 'solid' },
    { id: `${id}-ws`, a: [x1, z1], b: [x0, z1], t, kind: 'solid' },
    { id: `${id}-ww`, a: [x0, z1], b: [x0, z0], t, kind: 'solid' },
  ];
  const side = { n: `${id}-wn`, e: `${id}-we`, s: `${id}-ws`, w: `${id}-ww` };
  const openings = doors
    .map((d) => (typeof d === 'string' ? { side: d } : d))
    .map((d, k) => ({ id: `${id}-d${k}`, wall: side[d.side], at: d.at ?? 0.5, w: d.w ?? 1.2, kind: d.kind ?? 'door' }));
  return { space: { id, name, type, shape: { outer: rect(x0, z0, x1, z1), holes: [] } }, walls, openings };
}

export function level(id, name, elevation, parts, { outline = rect(0, 0, 40, 20), features = [], walls = [], openings = [], spaces = [] } = {}) {
  return {
    id,
    name,
    elevation,
    height: 4,
    offset: [0, 0],
    rot: 0,
    outline: outline ? { outer: outline, holes: [] } : null,
    walls: [...walls, ...parts.flatMap((p) => p.walls)],
    openings: [...openings, ...parts.flatMap((p) => p.openings)],
    spaces: [...spaces, ...parts.map((p) => p.space)],
    features,
  };
}

export function layoutOf(levels, connectors = [], building = {}) {
  const { layout, problems } = validateLayout({ spec: 1, units: 'm', catalog: 1, buildings: [{ id: 'bd-1', name: 'Main Mall', origin: [0, 0], rot: 0, levels, ...building }], connectors });
  assert.deepEqual(problems, [], 'the test layout is valid');
  return publishable(layout);
}

/** A corridor along z 8–12 between two rows of walled shops, an entrance at the west end. */
export function mallFloor() {
  const a = shop('sp-101', 'Unit 101', [2, 0, 12, 8], ['s']);
  const b = shop('sp-102', 'Unit 102', [14, 0, 24, 8], ['s']);
  const c = shop('sp-103', 'Unit 103', [2, 12, 12, 20], ['n', { side: 'e', at: 0.5 }]);
  const d = shop('sp-104', 'Unit 104', [14, 12, 24, 20], ['n']);
  const boundary = [
    { id: 'wb-w', a: [0, 0], b: [0, 20], t: 0.3, kind: 'boundary' },
    { id: 'wb-e', a: [40, 0], b: [40, 20], t: 0.3, kind: 'boundary' },
  ];
  return level('lv-g', 'Ground floor', 0, [a, b, c, d], {
    walls: boundary,
    openings: [{ id: 'op-main', wall: 'wb-w', at: 0.5, w: 3, kind: 'entrance', label: 'Main entrance' }],
  });
}

/** The phone's routing, simplified: both ways unless oneWay; hop costs as in kit_venue.dart. */
export function routes(pkg, fromNode, { avoidThrough = false, minWidth = 0 } = {}) {
  const pos = new Map(pkg.graph.nodes.map((n) => [n.id, n]));
  const elev = pkg.levels.map((l) => l.elev);
  const hop = (t, dz) => ({ lift: 30 + 1.5 * dz, stairs: 34 + 3 * dz, escalator: 14 + dz }[t] ?? 20 + 2 * dz);
  const adj = new Map(pkg.graph.nodes.map((n) => [n.id, []]));
  for (const e of pkg.graph.edges) {
    if (avoidThrough && e.through) continue;
    if (minWidth && (e.w ?? 3) < minWidth) continue;
    const a = pos.get(e.a);
    const b = pos.get(e.b);
    const cost = e.cost != null ? e.cost : e.kind === 'hop' ? hop(e.ctype ?? 'stairs', Math.abs(elev[b.lv] - elev[a.lv])) : Math.hypot(a.x - b.x, a.y - b.y);
    adj.get(e.a).push([e.b, cost]);
    if (!e.oneWay) adj.get(e.b).push([e.a, cost]);
  }
  const dist = new Map([[fromNode, 0]]);
  const todo = [[0, fromNode]];
  while (todo.length) {
    todo.sort((x, y) => x[0] - y[0] || (x[1] < y[1] ? -1 : 1));
    const [d, n] = todo.shift();
    if (d > dist.get(n)) continue;
    for (const [m, c] of adj.get(n)) {
      if (!dist.has(m) || d + c < dist.get(m) - 1e-9) {
        dist.set(m, d + c);
        todo.push([d + c, m]);
      }
    }
  }
  return dist;
}

/** The published fixtures for the mobile loader test: name → { layout, links, appCategories }. */
export function fixtures() {
  const corridor = {
    layout: layoutOf([mallFloor()]),
    links: [
      { spaceKey: 'sp-101', storeId: 345, storeName: 'Uniqlo' },
      { spaceKey: 'sp-103', storeId: 346, storeName: 'Corner Books' },
    ],
    appCategories: { 345: 'fashion', 346: 'books' },
  };
  const floors = [0, 5, 10].map((e, k) =>
    level(`lv-${k}`, k === 0 ? 'Ground floor' : `Level ${k + 1}`, e, k === 0 ? [] : [shop(`sp-${k}`, `Shop ${k}`, [2, 0, 10, 6], ['s'])], {
      features: k === 0 ? [{ id: 'ft-in', type: 'entrance', x: 1, z: 15 }] : [],
    }),
  );
  const twoLevels = {
    layout: layoutOf(floors, [
      { id: 'cn-lift', kind: 'elevator', name: 'West lifts', endpoints: [0, 1, 2].map((k) => ({ level: `lv-${k}`, x: 30, z: 15 })) },
      { id: 'cn-esc', kind: 'escalator', name: 'Down escalator', oneWay: true, endpoints: [{ level: 'lv-1', x: 20, z: 15 }, { level: 'lv-0', x: 20, z: 15 }] },
    ]),
    links: [],
    appCategories: {},
  };
  const rotated = { layout: layoutOf([{ ...mallFloor(), rot: 30, offset: [5, -3] }], [], { origin: [100, 50], rot: 90 }), links: [], appCategories: {} };
  // A 0.9 m door (wheelchair routes avoid it) beside a 1.5 m one into the same shop.
  const narrow = shop('sp-n', 'Narrow Door Shop', [14, 0, 24, 8], [{ side: 's', at: 0.25, w: 0.9 }]);
  const wide = shop('sp-w', 'Wide Door Shop', [2, 0, 12, 8], [{ side: 's', w: 1.5 }]);
  const doors = { layout: layoutOf([level('lv-g', 'Ground floor', 0, [narrow, wide], { features: [{ id: 'ft-in', type: 'entrance', x: 1, z: 15 }] })]), links: [], appCategories: {} };
  return { corridor, 'two-levels': twoLevels, rotated, doors };
}
