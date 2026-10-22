// The map document → simple 3D shapes (Round 17, US-036). Pure: no three.js and
// no DOM, so it runs in Node tests. World axes: x right, z down the plan (as in
// 2D), y up. Rotations in the document are degrees clockwise on the plan.
//
// Input: { doc, levelId, proposal, problems: [ids], featureSizes: {type: [w,d,h]}, colors }
// Output: { levels: [{ id, key, opacity, boxes, floors, labels }], links, bounds }
//   box   = { id, x, y, z, sx, sy, sz, rotY, color, opacity, rise }
//   floor = { id, y, points: [[x,z]...], holes, color, opacity }
//   label = { x, y, z, text, color, opacity }
//   link  = { a: [x,y,z], b: [x,y,z], color, opacity }

export const DOOR_HEIGHT = 2.1;
export const SILL = 0.9;
// Round 18 (nicer 3D): door frames are thin posts and a header around each opening.
export const FRAME = 0.06;
const FADED = 0.28;

const rad = (deg) => ((Number(deg) || 0) * Math.PI) / 180;

/** Level-local plan point → world plan point (level rot + offset, then building rot + origin). */
export function placer(building, level) {
  const lr = rad(level.rot);
  const br = rad(building.rot);
  const [ox, oz] = level.offset ?? [0, 0];
  const [bx, bz] = building.origin ?? [0, 0];
  const lc = Math.cos(lr), ls = Math.sin(lr), bc = Math.cos(br), bs = Math.sin(br);
  return ([x, z]) => {
    const x1 = x * lc - z * ls + ox;
    const z1 = x * ls + z * lc + oz;
    return [x1 * bc - z1 * bs + bx, x1 * bs + z1 * bc + bz];
  };
}

/** A box along a plan segment p→q (world), from y0 to y1. */
function segmentBox(p, q, t, y0, y1, extra) {
  const dx = q[0] - p[0];
  const dz = q[1] - p[1];
  const len = Math.hypot(dx, dz);
  return {
    x: (p[0] + q[0]) / 2,
    z: (p[1] + q[1]) / 2,
    y: (y0 + y1) / 2,
    sx: Math.max(len, 0.01),
    sy: Math.max(y1 - y0, 0.01),
    sz: Math.max(t, 0.03),
    rotY: Math.atan2(-dz, dx),
    ...extra,
  };
}

/**
 * Wall → boxes: full-height pieces between openings, lintels above doors, sills
 * under windows, and (Round 18) a frame around each door: two posts and a header.
 * Frames use style.frame (colour) when given; entrances use style.entrance.
 */
export function wallBoxes(wall, openings, place, base, height, style) {
  const a = place(wall.a);
  const b = place(wall.b);
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
  if (len < 0.01) return [];
  const at = (s) => [a[0] + ((b[0] - a[0]) * s) / len, a[1] + ((b[1] - a[1]) * s) / len];
  const gaps = openings
    .map((o) => ({ s: Math.max(0, o.at * len - o.w / 2), e: Math.min(len, o.at * len + o.w / 2), kind: o.kind }))
    .filter((g) => g.e > g.s)
    .sort((g, h) => g.s - h.s);
  const top = base + height;
  const out = [];
  let cursor = 0;
  for (const g of gaps) {
    if (g.s > cursor + 0.005) out.push(segmentBox(at(cursor), at(g.s), wall.t, base, top, style));
    const doorTop = base + Math.min(DOOR_HEIGHT, height);
    if (top > doorTop + 0.01) out.push(segmentBox(at(g.s), at(g.e), wall.t, doorTop, top, style));
    if (g.kind === 'window') out.push(segmentBox(at(g.s), at(g.e), wall.t, base, base + Math.min(SILL, height), style));
    if (style.frame && g.kind !== 'window' && g.kind !== 'passage' && g.e - g.s > 3 * FRAME) {
      const frame = { id: style.id, color: g.kind === 'entrance' ? style.entrance ?? style.frame : style.frame, opacity: style.opacity, material: 'frame', rise: style.rise };
      const depth = wall.t + 0.03;
      out.push(segmentBox(at(g.s), at(g.s + FRAME), depth, base, doorTop, frame));
      out.push(segmentBox(at(g.e - FRAME), at(g.e), depth, base, doorTop, frame));
      out.push(segmentBox(at(g.s), at(g.e), depth, doorTop - FRAME, doorTop, frame));
    }
    cursor = Math.max(cursor, g.e);
  }
  if (len > cursor + 0.005) out.push(segmentBox(at(cursor), b, wall.t, base, top, style));
  return out;
}

function centroid(points) {
  let x = 0, z = 0;
  for (const p of points) {
    x += p[0];
    z += p[1];
  }
  return [x / points.length, z / points.length];
}

/** A cheap fingerprint, so the scene rebuilds only the levels that changed. */
export function keyOf(value) {
  const s = JSON.stringify(value);
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return `${s.length}:${(h >>> 0).toString(36)}`;
}

export function buildModel(input) {
  const { doc, levelId, proposal = null, problems = [], featureSizes = {}, colors = {} } = input ?? {};
  const bad = new Set(problems);
  const unsure = new Set(proposal?.uncertain ?? []);
  const c = {
    wall: '#3a3a44',
    boundary: '#24242b',
    glass: '#7cc7e8',
    slab: '#e9e9ef',
    room: '#cfcfd8',
    label: '#1a1a1f',
    feature: '#f08a5d',
    connector: '#8b5cf6',
    proposal: '#0d9488',
    unsure: '#d97706',
    problem: '#dc2626',
    frame: '#8a8a95',
    entrance: '#ff5a3d',
    roomEdge: '#ffffff',
    ...colors,
  };
  const roomColors = colors.rooms ?? {};
  const levels = [];
  const links = [];
  const where = new Map(); // level id → { place, elevation, opacity }
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  const grow = (x, y, z) => {
    if (x < min[0]) min[0] = x;
    if (y < min[1]) min[1] = y;
    if (z < min[2]) min[2] = z;
    if (x > max[0]) max[0] = x;
    if (y > max[1]) max[1] = y;
    if (z > max[2]) max[2] = z;
  };

  for (const building of doc?.buildings ?? []) {
    for (const level of building.levels ?? []) {
      const place = placer(building, level);
      const current = level.id === levelId;
      const opacity = current ? 1 : FADED;
      const base = Number(level.elevation) || 0;
      const height = Math.max(2, Number(level.height) || 4);
      where.set(level.id, { place, base, opacity });
      const boxes = [];
      const floors = [];
      const labels = [];

      if (level.outline?.outer?.length >= 3) {
        floors.push({ id: `${level.id}-slab`, y: base, points: level.outline.outer.map(place), holes: (level.outline.holes ?? []).map((h) => h.map(place)), color: c.slab, opacity, slab: true });
      }
      for (const s of level.spaces ?? []) {
        if (!(s.shape?.outer?.length >= 3)) continue;
        const pts = s.shape.outer.map(place);
        floors.push({
          id: s.id,
          y: base + 0.02,
          points: pts,
          holes: (s.shape.holes ?? []).map((h) => h.map(place)),
          color: bad.has(s.id) ? c.problem : roomColors[s.type] ?? c.room,
          opacity,
          finish: s.type === 'corridor' || s.type === 'atrium' ? 'gloss' : 'matte',
          edge: c.roomEdge,
        });
        if (current && s.name) {
          const [x, z] = centroid(pts);
          labels.push({ x, y: base + 0.6, z, text: s.name, color: c.label, opacity });
        }
      }
      const byWall = new Map();
      for (const o of level.openings ?? []) {
        if (!byWall.has(o.wall)) byWall.set(o.wall, []);
        byWall.get(o.wall).push(o);
      }
      for (const w of level.walls ?? []) {
        const glass = w.kind === 'glass';
        const color = bad.has(w.id) ? c.problem : glass ? c.glass : w.kind === 'boundary' ? c.boundary : c.wall;
        const op = glass ? Math.min(opacity, 0.35) : opacity;
        // Glass is thin (6 mm board in a frame), whatever thickness was drawn.
        const wall = glass ? { ...w, t: Math.min(w.t ?? 0.1, 0.05) } : w;
        boxes.push(...wallBoxes(wall, byWall.get(w.id) ?? [], place, base, height, { id: w.id, color, opacity: op, material: glass ? 'glass' : 'wall', frame: c.frame, entrance: c.entrance }));
      }
      for (const f of level.features ?? []) {
        const size = featureSizes[f.type] ?? [1, 1, 1];
        const sx = Number(f.w) || size[0];
        const sz = Number(f.d) || size[1];
        const sy = Number(f.h) || size[2];
        const [x, z] = place([f.x, f.z]);
        boxes.push({ id: f.id, x, y: base + sy / 2, z, sx, sy, sz, rotY: -rad(f.rot) - rad(level.rot) - rad(building.rot), color: bad.has(f.id) ? c.problem : c.feature, opacity });
      }

      // The AI proposal for this level: teal, unsure pieces amber, rising in.
      if (proposal && proposal.levelId === level.id) {
        const pw = new Map();
        for (const o of proposal.openings ?? []) {
          if (!pw.has(o.wall)) pw.set(o.wall, []);
          pw.get(o.wall).push(o);
        }
        for (const w of proposal.walls ?? []) {
          const color = unsure.has(w.id) ? c.unsure : c.proposal;
          boxes.push(...wallBoxes(w, pw.get(w.id) ?? [], place, base, height, { id: w.id, color, opacity: 0.9, rise: true, material: w.kind === 'glass' ? 'glass' : 'wall', frame: color, entrance: color }));
        }
        for (const s of proposal.spaces ?? []) {
          if (!(s.shape?.outer?.length >= 3)) continue;
          const pts = s.shape.outer.map(place);
          floors.push({ id: s.id, y: base + 0.04, points: pts, holes: [], color: unsure.has(s.id) ? c.unsure : c.proposal, opacity: 0.35, proposal: true });
          if (s.name) {
            const [x, z] = centroid(pts);
            labels.push({ x, y: base + 0.6, z, text: s.name, color: c.proposal, opacity: 1 });
          }
        }
        if (proposal.outline?.outer?.length >= 3 && !level.outline) {
          floors.push({ id: `${level.id}-ai-slab`, y: base, points: proposal.outline.outer.map(place), holes: [], color: c.proposal, opacity: 0.18, proposal: true });
        }
      }

      for (const b of boxes) {
        grow(b.x - b.sx / 2, b.y - b.sy / 2, b.z - b.sx / 2);
        grow(b.x + b.sx / 2, b.y + b.sy / 2, b.z + b.sx / 2);
      }
      for (const f of floors) for (const [x, z] of f.points) grow(x, f.y, z);
      levels.push({ id: level.id, name: level.name, elevation: base, current, opacity, boxes, floors, labels, key: keyOf([boxes, floors, labels]) });
    }
  }

  // Connectors: a pad on each level they reach, and a link between consecutive levels.
  for (const cn of doc?.connectors ?? []) {
    const ends = [];
    for (const e of cn.endpoints ?? []) {
      const lv = where.get(e.level);
      if (!lv) continue;
      const [x, z] = lv.place([e.x, e.z]);
      ends.push({ x, z, y: lv.base, opacity: lv.opacity });
      const lvl = levels.find((l) => l.id === e.level);
      lvl.boxes.push({ id: cn.id, x, y: lv.base + 0.08, z, sx: Number(e.w) || 1.4, sy: 0.16, sz: Number(e.len) || 4, rotY: -rad(e.rot), color: bad.has(cn.id) ? c.problem : c.connector, opacity: lv.opacity });
      lvl.key = keyOf([lvl.key, cn]);
    }
    ends.sort((p, q) => p.y - q.y);
    for (let i = 1; i < ends.length; i++) {
      links.push({ id: cn.id, a: [ends[i - 1].x, ends[i - 1].y + 0.16, ends[i - 1].z], b: [ends[i].x, ends[i].y, ends[i].z], color: c.connector, opacity: Math.max(ends[i - 1].opacity, ends[i].opacity) });
    }
  }

  const empty = min[0] === Infinity;
  return { levels, links, bounds: empty ? { min: [0, 0, 0], max: [50, 4, 30] } : { min, max } };
}
