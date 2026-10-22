// Round 17 (US-036): the 3D preview's geometry builder lives in the web app
// (LIQo web/web/map3d/model.js) and has no DOM or three.js, so it is tested
// here with the rest of the Node tests.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildModel, wallBoxes, placer, DOOR_HEIGHT } from '../../LIQo web/web/map3d/model.js';

const level = (over = {}) => ({ id: 'lv-1', name: 'Ground', elevation: 0, height: 4, offset: [0, 0], rot: 0, outline: { outer: [[0, 0], [20, 0], [20, 10], [0, 10]], holes: [] }, walls: [], openings: [], spaces: [], features: [], ...over });
const doc = (levels, connectors = [], building = {}) => ({ buildings: [{ id: 'bd', name: 'Main', origin: [0, 0], rot: 0, levels, ...building }], connectors });

test('a wall with a door: two full pieces and a lintel above the door', () => {
  const place = placer({ origin: [0, 0], rot: 0 }, { offset: [0, 0], rot: 0 });
  const boxes = wallBoxes({ id: 'w', a: [0, 0], b: [10, 0], t: 0.2 }, [{ at: 0.5, w: 1, kind: 'door' }], place, 0, 4, {});
  assert.equal(boxes.length, 3);
  const [left, lintel, right] = boxes;
  assert.ok(Math.abs(left.sx - 4.5) < 1e-9 && Math.abs(right.sx - 4.5) < 1e-9);
  assert.ok(Math.abs(lintel.sx - 1) < 1e-9);
  assert.ok(Math.abs(lintel.y - (DOOR_HEIGHT + 4) / 2) < 1e-9, 'the lintel spans door top to ceiling');
  assert.ok(Math.abs(left.sy - 4) < 1e-9);
});

test('a window keeps a sill under it', () => {
  const place = placer({ origin: [0, 0], rot: 0 }, { offset: [0, 0], rot: 0 });
  const boxes = wallBoxes({ id: 'w', a: [0, 0], b: [4, 0], t: 0.2 }, [{ at: 0.5, w: 2, kind: 'window' }], place, 0, 3, {});
  assert.equal(boxes.length, 4, 'left, lintel, sill, right');
});

test('levels stack by elevation; the current one is solid, the others faded', () => {
  const m = buildModel({ doc: doc([level(), level({ id: 'lv-2', elevation: 5, walls: [{ id: 'w2', a: [0, 0], b: [5, 0], t: 0.2, kind: 'solid' }] })]), levelId: 'lv-1' });
  assert.equal(m.levels.length, 2);
  const [g, second] = m.levels;
  assert.equal(g.opacity, 1);
  assert.ok(second.opacity < 0.5);
  assert.ok(Math.abs(second.boxes[0].y - 7) < 1e-9, 'the upper wall sits from 5 to 9 m');
});

test('building rotation and origin move the whole floor', () => {
  const m = buildModel({ doc: doc([level({ walls: [{ id: 'w', a: [0, 0], b: [10, 0], t: 0.2 }] })], [], { origin: [100, 50], rot: 90 }), levelId: 'lv-1' });
  const w = m.levels[0].boxes[0];
  // Turned 90° clockwise on the plan: the wall now runs down z from (100, 50).
  assert.ok(Math.abs(w.x - 100) < 1e-9 && Math.abs(w.z - 55) < 1e-9);
});

test('the AI proposal is teal, unsure pieces amber, rising in; problems never hidden', () => {
  const m = buildModel({
    doc: doc([level({ walls: [{ id: 'bad-wall', a: [0, 0], b: [3, 0], t: 0.2 }] })]),
    levelId: 'lv-1',
    problems: ['bad-wall'],
    colors: { proposal: '#00aa99', unsure: '#ffaa00', problem: '#ff0000' },
    proposal: {
      levelId: 'lv-1',
      walls: [{ id: 'ai-w-1', a: [0, 5], b: [10, 5], t: 0.2 }, { id: 'ai-w-2', a: [10, 5], b: [10, 9], t: 0.1 }],
      openings: [],
      spaces: [{ id: 'ai-sp-1', name: 'Zara', type: 'retail', shape: { outer: [[0, 0], [10, 0], [10, 5], [0, 5]] } }],
      uncertain: ['ai-w-2'],
    },
  });
  const boxes = m.levels[0].boxes;
  assert.equal(boxes.find((b) => b.id === 'bad-wall').color, '#ff0000');
  assert.equal(boxes.find((b) => b.id === 'ai-w-1').color, '#00aa99');
  assert.equal(boxes.find((b) => b.id === 'ai-w-2').color, '#ffaa00');
  assert.ok(boxes.filter((b) => b.id.startsWith('ai-')).every((b) => b.rise));
  assert.ok(m.levels[0].labels.some((l) => l.text === 'Zara'));
});

test('features use their size; connectors put pads on both levels and a link between', () => {
  const m = buildModel({
    doc: doc(
      [level({ features: [{ id: 'f1', type: 'kiosk', x: 5, z: 5, rot: 0 }] }), level({ id: 'lv-2', elevation: 5 })],
      [{ id: 'c1', kind: 'escalator', endpoints: [{ level: 'lv-1', x: 2, z: 2, rot: 0, w: 1.2, len: 6 }, { level: 'lv-2', x: 2, z: 8, rot: 0, w: 1.2, len: 6 }] }],
    ),
    levelId: 'lv-1',
    featureSizes: { kiosk: [2, 2, 2.2] },
  });
  const kiosk = m.levels[0].boxes.find((b) => b.id === 'f1');
  assert.deepEqual([kiosk.sx, kiosk.sy, kiosk.sz], [2, 2.2, 2]);
  assert.ok(m.levels[0].boxes.some((b) => b.id === 'c1') && m.levels[1].boxes.some((b) => b.id === 'c1'));
  assert.equal(m.links.length, 1);
  assert.equal(m.links[0].b[1], 5);
});

test('an empty level still gives a model, and keys change only with the level', () => {
  const a = buildModel({ doc: doc([level({ outline: null })]), levelId: 'lv-1' });
  assert.equal(a.levels[0].boxes.length, 0);
  assert.ok(a.bounds.max[0] > a.bounds.min[0]);
  const b1 = buildModel({ doc: doc([level(), level({ id: 'lv-2', elevation: 5 })]), levelId: 'lv-1' });
  const b2 = buildModel({ doc: doc([level(), level({ id: 'lv-2', elevation: 5, walls: [{ id: 'w', a: [0, 0], b: [2, 0], t: 0.2 }] })]), levelId: 'lv-1' });
  assert.equal(b1.levels[0].key, b2.levels[0].key);
  assert.notEqual(b1.levels[1].key, b2.levels[1].key);
});

// Round 18 (owner: "a nicer 3D look"): door frames, thin see-through glass,
// entrances in the accent colour, room finishes and edges.
test('doors get a frame (two posts and a header); entrances use the accent colour', () => {
  const place = placer({ origin: [0, 0], rot: 0 }, { offset: [0, 0], rot: 0 });
  const style = { id: 'w', color: '#333333', opacity: 1, frame: '#888888', entrance: '#ff5a3d' };
  const door = wallBoxes({ id: 'w', a: [0, 0], b: [10, 0], t: 0.2 }, [{ at: 0.5, w: 1, kind: 'door' }], place, 0, 4, style);
  const frames = door.filter((b) => b.material === 'frame');
  assert.equal(frames.length, 3, 'two posts and a header');
  assert.ok(frames.every((f) => f.color === '#888888'));
  assert.ok(frames.every((f) => f.sz > 0.2), 'a frame stands a little proud of the wall');
  const entrance = wallBoxes({ id: 'w', a: [0, 0], b: [10, 0], t: 0.2 }, [{ at: 0.5, w: 3, kind: 'entrance' }], place, 0, 4, style);
  assert.ok(entrance.filter((b) => b.material === 'frame').every((f) => f.color === '#ff5a3d'));
  const passage = wallBoxes({ id: 'w', a: [0, 0], b: [10, 0], t: 0.2 }, [{ at: 0.5, w: 2, kind: 'passage' }], place, 0, 4, style);
  assert.equal(passage.filter((b) => b.material === 'frame').length, 0, 'an open passage has no frame');
});

test('glass is thin and see-through; rooms carry a finish and an edge', () => {
  const m = buildModel({
    doc: doc([level({
      walls: [{ id: 'g', a: [0, 0], b: [5, 0], t: 0.2, kind: 'glass' }, { id: 's', a: [0, 5], b: [5, 5], t: 0.2, kind: 'solid' }],
      spaces: [
        { id: 'c', name: 'Mall', type: 'corridor', shape: { outer: [[0, 0], [5, 0], [5, 5], [0, 5]] } },
        { id: 'r', name: 'Shop', type: 'retail', shape: { outer: [[5, 0], [9, 0], [9, 5], [5, 5]] } },
      ],
    })]),
    levelId: 'lv-1',
  });
  const glass = m.levels[0].boxes.find((b) => b.id === 'g');
  assert.equal(glass.material, 'glass');
  assert.ok(glass.sz <= 0.05 && glass.opacity <= 0.35);
  assert.equal(m.levels[0].boxes.find((b) => b.id === 's').material, 'wall');
  assert.equal(m.levels[0].floors.find((f) => f.id === 'c').finish, 'gloss');
  assert.equal(m.levels[0].floors.find((f) => f.id === 'r').finish, 'matte');
  assert.ok(m.levels[0].floors.find((f) => f.id === 'r').edge);
});
