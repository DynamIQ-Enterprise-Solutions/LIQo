// Measured walls and rooms (Round 18, owner decision 2026-10-22: "measured walls
// + AI names"). A vision model only estimates lines (a few percent of the
// picture off), so walls are measured from the picture's own pixels and the AI
// adds what pixels cannot tell: names, types, doors and glass (spec §10.2).
//
// What makes a wall on a drawn plan is two long parallel ink lines 6–28 cm apart
// (the two faces of a wall band). Desks (0.6 m deep), chairs, text strokes and
// single dimension lines do not have that shape.
//   1. grey → ink mask, min-pooled to ~100 px/m so thin lines survive;
//   2. long ink runs along rows and columns (axis-aligned walls);
//   3. same-direction bands 6–28 cm apart overlapping ≥ 0.5 m → wall centre lines;
//   4. collinear pieces merged; a collinear gap of 0.6–2.6 m is a door;
//   5. pixels → level metres through the backdrop calibration.
// Rooms are then the areas the walls enclose (filled like paint), and the floor
// outline is the edge of everything inside (roomsFromWalls).

const TARGET_PX_PER_M = 100;

// ---- ink mask ----

function inkMask(img, factor) {
  const { width, height, data } = img;
  const w = Math.ceil(width / factor);
  const h = Math.ceil(height / factor);
  // Grey histogram for a simple threshold between paper and ink (Otsu).
  const hist = new Uint32Array(256);
  for (let p = 0; p < width * height; p += 7) {
    const o = p * 4;
    const g = data[o + 3] < 16 ? 255 : (data[o] * 299 + data[o + 1] * 587 + data[o + 2] * 114) / 1000;
    hist[g | 0] += 1;
  }
  let total = 0;
  let sum = 0;
  for (let i = 0; i < 256; i++) {
    total += hist[i];
    sum += i * hist[i];
  }
  let sumB = 0;
  let wB = 0;
  let bestVar = -1;
  let threshold = 128;
  for (let t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB === 0) continue;
    const wF = total - wB;
    if (wF === 0) break;
    sumB += t * hist[t];
    const mB = sumB / wB;
    const mF = (sum - sumB) / wF;
    const v = wB * wF * (mB - mF) * (mB - mF);
    if (v > bestVar) {
      bestVar = v;
      // Halfway between the two class means, so pure-ink pixels count as ink.
      threshold = (mB + mF) / 2;
    }
  }
  threshold = Math.min(200, Math.max(40, threshold));

  const mask = new Uint8Array(w * h);
  for (let y = 0; y < height; y++) {
    const my = (y / factor) | 0;
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      if (data[o + 3] < 16) continue;
      const g = (data[o] * 299 + data[o + 1] * 587 + data[o + 2] * 114) / 1000;
      if (g < threshold) mask[my * w + ((x / factor) | 0)] = 1;
    }
  }
  return { mask, w, h };
}

// ---- runs and bands ----

/** Ink runs along one row (or column when `vertical`), bridging gaps ≤ gapPx. */
function runsAlong(mask, w, h, index, vertical, minLenPx, gapPx) {
  const len = vertical ? h : w;
  const at = (i) => (vertical ? mask[i * w + index] : mask[index * w + i]);
  const runs = [];
  let start = -1;
  let last = -1;
  for (let i = 0; i < len; i++) {
    if (at(i)) {
      if (start < 0) start = i;
      last = i;
    } else if (start >= 0 && i - last > gapPx) {
      if (last - start + 1 >= minLenPx) runs.push([start, last]);
      start = -1;
    }
  }
  if (start >= 0 && last - start + 1 >= minLenPx) runs.push([start, last]);
  return runs;
}

/** Groups runs on adjacent rows into bands (a drawn line has some thickness). */
function bands(mask, w, h, vertical, pxPerM) {
  const minLen = Math.round(0.7 * pxPerM);
  const gap = Math.max(1, Math.round(0.03 * pxPerM));
  const count = vertical ? w : h;
  const open = [];
  const done = [];
  for (let idx = 0; idx < count; idx++) {
    const runs = runsAlong(mask, w, h, idx, vertical, minLen, gap);
    const next = [];
    for (const [a, b] of runs) {
      let joined = null;
      for (const band of open) {
        if (band.pos1 === idx - 1 && a <= band.b && b >= band.a) {
          joined = band;
          break;
        }
      }
      if (joined) {
        joined.pos1 = idx;
        joined.a = Math.min(joined.a, a);
        joined.b = Math.max(joined.b, b);
        next.push(joined);
      } else {
        next.push({ pos0: idx, pos1: idx, a, b });
      }
    }
    for (const band of open) if (!next.includes(band)) done.push(band);
    open.length = 0;
    open.push(...next);
  }
  done.push(...open);
  // Thin bands (ink lines), not filled areas.
  const maxThick = Math.round(0.08 * pxPerM) + 1;
  return done.filter((b) => b.pos1 - b.pos0 + 1 <= maxThick).map((b) => ({ pos: (b.pos0 + b.pos1) / 2, a: b.a, b: b.b }));
}

/** Pairs parallel bands 6–28 cm apart overlapping ≥ 0.5 m into wall centre lines. */
function pairBands(list, pxPerM) {
  const minGap = 0.06 * pxPerM;
  const maxGap = 0.28 * pxPerM;
  const minOverlap = 0.5 * pxPerM;
  const sorted = [...list].sort((x, y) => x.pos - y.pos);
  const used = new Set();
  const walls = [];
  for (let i = 0; i < sorted.length; i++) {
    if (used.has(i)) continue;
    for (let j = i + 1; j < sorted.length; j++) {
      if (used.has(j)) continue;
      const d = sorted[j].pos - sorted[i].pos;
      if (d > maxGap) break;
      if (d < minGap) continue;
      const a = Math.max(sorted[i].a, sorted[j].a);
      const b = Math.min(sorted[i].b, sorted[j].b);
      if (b - a < minOverlap) continue;
      walls.push({ pos: (sorted[i].pos + sorted[j].pos) / 2, a, b, t: d });
      used.add(i);
      used.add(j);
      break;
    }
  }
  return walls;
}

/** Merges collinear overlapping or touching pieces. */
function mergeCollinear(walls, pxPerM) {
  const tol = 0.03 * pxPerM;
  const sorted = [...walls].sort((x, y) => x.pos - y.pos || x.a - y.a);
  const out = [];
  for (const w of sorted) {
    const last = out[out.length - 1];
    if (last && Math.abs(last.pos - w.pos) <= tol && w.a <= last.b + tol) {
      last.b = Math.max(last.b, w.b);
      last.t = (last.t + w.t) / 2;
      last.pos = (last.pos + w.pos) / 2;
    } else {
      out.push({ ...w });
    }
  }
  return out;
}

/** Collinear gaps of 0.6–2.6 m become doors: the pieces are joined and an opening placed. */
function doorsFromGaps(walls, pxPerM) {
  const tol = 0.03 * pxPerM;
  const minDoor = 0.6 * pxPerM;
  const maxDoor = 2.6 * pxPerM;
  const sorted = [...walls].sort((x, y) => x.pos - y.pos || x.a - y.a);
  const out = [];
  for (const w of sorted) {
    const last = out[out.length - 1];
    if (last && Math.abs(last.pos - w.pos) <= tol && w.a > last.b) {
      const gap = w.a - last.b;
      if (gap >= minDoor && gap <= maxDoor) {
        last.openings.push({ at: last.b + gap / 2, w: gap });
        last.b = Math.max(last.b, w.b);
        continue;
      }
    }
    out.push({ ...w, openings: w.openings ? [...w.openings] : [] });
  }
  return out;
}

const r3 = (n) => Math.round(n * 1000) / 1000;

/**
 * Measures the walls of a plan picture.
 * @param img   decoded RGBA {width, height, data}
 * @param calib backdrop placement in level metres {cx, cz, mpp, rot}
 * @param opts  {crop?: [x0,y0,x1,y1] fractions}
 * @returns {walls: [{a,b,t,openings:[{at,w}]}] in level metres, stats, enough}
 */
export function measurePlan(img, calib, opts = {}) {
  const srcPxPerM = 1 / calib.mpp;
  const factor = Math.max(1, Math.floor(srcPxPerM / TARGET_PX_PER_M));
  const pxPerM = srcPxPerM / factor;
  const { mask, w, h } = inkMask(img, factor);

  if (opts.crop) {
    const [fx0, fy0, fx1, fy1] = opts.crop;
    const x0 = Math.floor(Math.min(fx0, fx1) * w);
    const y0 = Math.floor(Math.min(fy0, fy1) * h);
    const x1 = Math.ceil(Math.max(fx0, fx1) * w);
    const y1 = Math.ceil(Math.max(fy0, fy1) * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (x < x0 || x >= x1 || y < y0 || y >= y1) mask[y * w + x] = 0;
  }

  const hWalls = doorsFromGaps(mergeCollinear(pairBands(bands(mask, w, h, false, pxPerM), pxPerM), pxPerM), pxPerM);
  const vWalls = doorsFromGaps(mergeCollinear(pairBands(bands(mask, w, h, true, pxPerM), pxPerM), pxPerM), pxPerM);
  const segments = [
    ...hWalls.map((x) => ({ x0: x.a, y0: x.pos, x1: x.b, y1: x.pos, t: x.t, openings: x.openings, horizontal: true })),
    ...vWalls.map((x) => ({ x0: x.pos, y0: x.a, x1: x.pos, y1: x.b, t: x.t, openings: x.openings, horizontal: false })),
  ];
  const totalLen = segments.reduce((s, x) => s + Math.hypot(x.x1 - x.x0, x.y1 - x.y0), 0) / pxPerM;

  // Downsampled px → source px → metres from the picture centre → rotate → translate.
  const rad = (calib.rot * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  const toLevel = (px, py) => {
    const mx = (px * factor - img.width / 2) * calib.mpp;
    const mz = (py * factor - img.height / 2) * calib.mpp;
    return [r3(calib.cx + mx * cos - mz * sin), r3(calib.cz + mx * sin + mz * cos)];
  };
  const walls = segments.map((s) => {
    const len = s.horizontal ? s.x1 - s.x0 : s.y1 - s.y0;
    return {
      a: toLevel(s.x0, s.y0),
      b: toLevel(s.x1, s.y1),
      t: r3(Math.min(1, Math.max(0.05, s.t / pxPerM))),
      openings: (s.openings ?? []).map((o) => ({
        at: r3(Math.min(1, Math.max(0, len > 0 ? (o.at - (s.horizontal ? s.x0 : s.y0)) / len : 0.5))),
        w: r3(Math.min(6, Math.max(0.6, o.w / pxPerM))),
      })),
    };
  });
  return {
    walls,
    stats: { walls: walls.length, doors: walls.reduce((n, x) => n + x.openings.length, 0), wallMetres: Math.round(totalLen), pxPerM: Math.round(pxPerM) },
    // Spec: under ~8 m of wall or 4 pieces the picture is not a readable plan here.
    enough: segments.length >= 4 && totalLen >= 8,
  };
}

// ---------------------------------------------------------------------------
// Rooms from walls (level metres)
// ---------------------------------------------------------------------------

/** Douglas–Peucker on a closed ring. */
function simplify(pts, tol) {
  if (pts.length < 4) return pts;
  const keep = new Uint8Array(pts.length);
  keep[0] = 1;
  keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let maxD = 0;
    let idx = -1;
    const [x0, y0] = pts[s];
    const [x1, y1] = pts[e];
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len = Math.hypot(dx, dy) || 1;
    for (let i = s + 1; i < e; i++) {
      const d = Math.abs(dy * pts[i][0] - dx * pts[i][1] + x1 * y0 - y1 * x0) / len;
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > tol && idx > 0) {
      keep[idx] = 1;
      stack.push([s, idx], [idx, e]);
    }
  }
  const out = [];
  for (let i = 0; i < pts.length; i++) if (keep[i]) out.push(pts[i]);
  if (out.length > 1 && out[0][0] === out[out.length - 1][0] && out[0][1] === out[out.length - 1][1]) out.pop();
  return out;
}

/** Drops near-duplicate points and points on a straight line between their neighbours. */
export function tidyRing(ring, tol = 0.6) {
  const pts = ring.slice();
  // Straight-line points first (so a true corner is never the one dropped),
  // then points that sit right on top of their neighbour.
  for (const pass of ['straight', 'close']) {
    let changed = true;
    while (changed && pts.length > 3) {
      changed = false;
      for (let i = 0; i < pts.length && pts.length > 3; i++) {
        const p = pts[(i - 1 + pts.length) % pts.length];
        const q = pts[i];
        const r = pts[(i + 1) % pts.length];
        const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
        // How far a point sits off the line between two others.
        const off = (x, a, b) => Math.abs((b[0] - a[0]) * (x[1] - a[1]) - (b[1] - a[1]) * (x[0] - a[0])) / (dist(a, b) || 1);
        let drop = -1;
        if (pass === 'straight') {
          // Near-duplicates are left to the next pass: they would fool this test.
          if (dist(q, p) > tol && dist(q, r) > tol && off(q, p, r) <= tol * 0.5) drop = i;
        } else if (dist(q, p) <= tol) {
          // Of two points on top of each other, drop the one that bends the ring less.
          const pi = (i - 1 + pts.length) % pts.length;
          const pp = pts[(i - 2 + pts.length) % pts.length];
          drop = off(p, pp, r) <= off(q, pp, r) ? pi : i;
        }
        if (drop >= 0) {
          pts.splice(drop, 1);
          changed = true;
          i = Math.max(-1, Math.min(i, drop) - 2);
        }
      }
    }
  }
  return pts;
}

/** Boundary of the cells where inside(x, y) is true, starting from a given cell, as a ring of cell corners. */
function trace(inside, start, gw) {
  const edges = new Map();
  const seen = new Set([start]);
  const stack = [start];
  while (stack.length) {
    const c = stack.pop();
    const x = c % gw;
    const y = (c / gw) | 0;
    if (!inside(x, y - 1)) edges.set(`${x},${y}`, [x + 1, y]);
    if (!inside(x + 1, y)) edges.set(`${x + 1},${y}`, [x + 1, y + 1]);
    if (!inside(x, y + 1)) edges.set(`${x + 1},${y + 1}`, [x, y + 1]);
    if (!inside(x - 1, y)) edges.set(`${x},${y + 1}`, [x, y]);
    for (const [nx, ny] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) {
      if (!inside(nx, ny)) continue;
      const n = ny * gw + nx;
      if (!seen.has(n)) {
        seen.add(n);
        stack.push(n);
      }
    }
  }
  if (!edges.size) return [];
  let startKey = null;
  for (const k of edges.keys()) {
    if (startKey === null) startKey = k;
    else {
      const [ax, ay] = k.split(',').map(Number);
      const [bx, by] = startKey.split(',').map(Number);
      if (ay < by || (ay === by && ax < bx)) startKey = k;
    }
  }
  const pts = [];
  let key = startKey;
  const visited = new Set();
  while (key && !visited.has(key) && pts.length < 200000) {
    visited.add(key);
    pts.push(key.split(',').map(Number));
    const n = edges.get(key);
    if (!n) break;
    key = `${n[0]},${n[1]}`;
  }
  return tidyRing(simplify(pts, 1.5), 1.2);
}

/**
 * The areas the walls enclose, filled like paint, and the edge of everything
 * inside as the floor outline. Loose wall ends are bridged up to 0.7 m so a
 * corner left slightly open still closes (spec §10.2 lessons).
 * @param walls [{a:[x,z], b:[x,z], t}] in level metres
 * @returns {rooms: [{outer:[[x,z]...], cells, index}], outline: [[x,z]...]|null, grid}
 */
export function roomsFromWalls(walls, { cell = 0.1, minArea = 1, maxRooms = 500 } = {}) {
  if (!walls.length) return { rooms: [], outline: null, grid: null };
  let minX = Infinity, minZ = Infinity, maxX = -Infinity, maxZ = -Infinity;
  for (const w of walls) {
    for (const [x, z] of [w.a, w.b]) {
      minX = Math.min(minX, x);
      minZ = Math.min(minZ, z);
      maxX = Math.max(maxX, x);
      maxZ = Math.max(maxZ, z);
    }
  }
  minX -= 2;
  minZ -= 2;
  maxX += 2;
  maxZ += 2;
  // Keep the grid within ~6 million cells.
  const area = (maxX - minX) * (maxZ - minZ);
  cell = Math.max(cell, Math.sqrt(area / 6_000_000));
  const gw = Math.ceil((maxX - minX) / cell);
  const gh = Math.ceil((maxZ - minZ) / cell);
  const grid = new Uint8Array(gw * gh); // 1 = wall
  const toCell = (x, z) => [(x - minX) / cell, (z - minZ) / cell];
  const stamp = (cx, cy, r) => {
    const ix = cx | 0;
    const iy = cy | 0;
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        const gx = ix + dx;
        const gy = iy + dy;
        if (gx >= 0 && gy >= 0 && gx < gw && gy < gh) grid[gy * gw + gx] = 1;
      }
    }
  };
  const segs = walls.map((w) => ({ p: toCell(...w.a), q: toCell(...w.b), r: Math.max(0, Math.round((w.t ?? 0.15) / cell / 2)) }));
  for (const s of segs) {
    const len = Math.hypot(s.q[0] - s.p[0], s.q[1] - s.p[1]);
    const steps = Math.max(1, Math.ceil(len * 2));
    for (let i = 0; i <= steps; i++) stamp(s.p[0] + ((s.q[0] - s.p[0]) * i) / steps, s.p[1] + ((s.q[1] - s.p[1]) * i) / steps, s.r);
  }
  // Bridge loose ends: extend each end up to 0.7 m until it meets another wall.
  const reach = Math.round(0.7 / cell);
  for (const s of segs) {
    for (const [e, o] of [[s.p, s.q], [s.q, s.p]]) {
      const len = Math.hypot(e[0] - o[0], e[1] - o[1]) || 1;
      const ux = (e[0] - o[0]) / len;
      const uy = (e[1] - o[1]) / len;
      const path = [];
      let hit = false;
      for (let k = s.r + 1; k <= reach + s.r; k++) {
        const gx = (e[0] + ux * k) | 0;
        const gy = (e[1] + uy * k) | 0;
        if (gx < 0 || gy < 0 || gx >= gw || gy >= gh) break;
        if (grid[gy * gw + gx]) {
          hit = true;
          break;
        }
        path.push(gy * gw + gx);
      }
      if (hit) for (const i of path) grid[i] = 1;
    }
  }
  // Outside: flood from the border.
  const label = new Int32Array(gw * gh); // 0 none, -1 outside, n room
  const stack = [];
  const push = (i) => {
    if (grid[i] === 0 && label[i] === 0) {
      label[i] = -1;
      stack.push(i);
    }
  };
  for (let x = 0; x < gw; x++) {
    push(x);
    push((gh - 1) * gw + x);
  }
  for (let y = 0; y < gh; y++) {
    push(y * gw);
    push(y * gw + gw - 1);
  }
  while (stack.length) {
    const i = stack.pop();
    const x = i % gw;
    const y = (i / gw) | 0;
    if (x > 0) push(i - 1);
    if (x < gw - 1) push(i + 1);
    if (y > 0) push(i - gw);
    if (y < gh - 1) push(i + gw);
  }
  const minCells = Math.max(4, Math.round(minArea / (cell * cell)));
  const toLevel = ([cx, cy]) => [r3(minX + cx * cell), r3(minZ + cy * cell)];
  const rooms = [];
  let next = 1;
  for (let i = 0; i < gw * gh && rooms.length < maxRooms; i++) {
    if (grid[i] !== 0 || label[i] !== 0) continue;
    const id = next++;
    const cells = [];
    label[i] = id;
    const st = [i];
    while (st.length) {
      const c = st.pop();
      cells.push(c);
      const x = c % gw;
      const y = (c / gw) | 0;
      for (const n of [x > 0 ? c - 1 : -1, x < gw - 1 ? c + 1 : -1, y > 0 ? c - gw : -1, y < gh - 1 ? c + gw : -1]) {
        if (n >= 0 && grid[n] === 0 && label[n] === 0) {
          label[n] = id;
          st.push(n);
        }
      }
    }
    if (cells.length < minCells) continue;
    const ring = trace((x, y) => x >= 0 && y >= 0 && x < gw && y < gh && label[y * gw + x] === id, cells[0], gw);
    if (ring.length >= 3) rooms.push({ outer: ring.map(toLevel), cells, index: id });
  }
  // The floor outline: the edge of everything not outside (rooms and walls),
  // taken from the largest such region.
  let outline = null;
  // Largest connected inside region (stray pieces such as dimension marks are smaller).
  const seen = new Uint8Array(gw * gh);
  let start = -1;
  let bestSize = 0;
  for (let i = 0; i < gw * gh; i++) {
    if (label[i] === -1 || seen[i]) continue;
    let size = 0;
    const st = [i];
    seen[i] = 1;
    while (st.length) {
      const c = st.pop();
      size += 1;
      const x = c % gw;
      const y = (c / gw) | 0;
      for (const n of [x > 0 ? c - 1 : -1, x < gw - 1 ? c + 1 : -1, y > 0 ? c - gw : -1, y < gh - 1 ? c + gw : -1]) {
        if (n >= 0 && !seen[n] && label[n] !== -1) {
          seen[n] = 1;
          st.push(n);
        }
      }
    }
    if (size > bestSize) {
      bestSize = size;
      start = i;
    }
  }
  if (start >= 0) {
    const ring = trace((x, y) => x >= 0 && y >= 0 && x < gw && y < gh && label[y * gw + x] !== -1, start, gw);
    if (ring.length >= 3) outline = ring.map(toLevel);
  }
  return { rooms, outline, grid: { minX, minZ, cell, gw, gh, label } };
}

/** Is the level point inside the ring? */
export function pointInRing([x, y], ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/**
 * Names the filled rooms from the AI's rooms (spec §10.2): each filled room
 * takes the AI room covering most of it; a leftover AI room goes to an
 * unclaimed filled room holding ≥ 20% of it. Returns per filled room the AI
 * room index (or -1).
 */
export function nameRooms(filled, aiRooms) {
  const { grid } = filled;
  if (!grid || !aiRooms.length) return filled.rooms.map(() => -1);
  const { minX, minZ, cell } = grid;
  const centre = (c) => [minX + ((c % grid.gw) + 0.5) * cell, minZ + (((c / grid.gw) | 0) + 0.5) * cell];
  // For each filled room: cells covered by each AI room (sampled for speed).
  const cover = filled.rooms.map((r) => {
    const counts = new Array(aiRooms.length).fill(0);
    const step = Math.max(1, Math.floor(r.cells.length / 4000));
    for (let k = 0; k < r.cells.length; k += step) {
      const p = centre(r.cells[k]);
      for (let a = 0; a < aiRooms.length; a++) if (pointInRing(p, aiRooms[a])) counts[a] += step;
    }
    return counts;
  });
  const pick = filled.rooms.map(() => -1);
  const taken = new Set();
  filled.rooms.forEach((r, i) => {
    let best = -1;
    for (let a = 0; a < aiRooms.length; a++) if (cover[i][a] > 0 && (best < 0 || cover[i][a] > cover[i][best])) best = a;
    if (best >= 0 && cover[i][best] >= 0.3 * r.cells.length) {
      pick[i] = best;
      taken.add(best);
    }
  });
  // Leftover AI rooms: the unclaimed filled room holding the biggest share of it.
  const aiCells = aiRooms.map((_, a) => cover.reduce((n, c) => n + c[a], 0));
  for (let a = 0; a < aiRooms.length; a++) {
    if (taken.has(a) || aiCells[a] === 0) continue;
    let best = -1;
    filled.rooms.forEach((_, i) => {
      if (pick[i] >= 0) return;
      if (cover[i][a] >= 0.2 * aiCells[a] && (best < 0 || cover[i][a] > cover[best][a])) best = i;
    });
    if (best >= 0) {
      pick[best] = a;
      taken.add(a);
    }
  }
  return pick;
}
