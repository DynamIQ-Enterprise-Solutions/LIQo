// One editor level's part of the shopper graph (Round 21, P1-08), in level
// metres: the walkway network (skeleton.js) plus doors, rooms, places,
// cut-throughs, exits and connector stops joined onto it. build.js moves
// everything to the branch frame and merges the levels.
import { FEATURE_TYPES } from '../catalog.js';
import { CLEAR, isWalkableSpace, OUTDOOR_TYPES } from './area.js';
import { skeleton } from './skeleton.js';
import { lineOk, simplifyLine, inPolygon } from './raster.js';

const ATTACH_REACH = 25; // metres searched for the network from a point
const VIRTUAL_STEP = 0.25;
const VIRTUAL_REACH = 1.0;
const MIN_DOOR = 0.8;

const OPENING_LABEL = { door: 'the door', entrance: 'the entrance', gate: 'the gate', passage: 'the passage', shutter: 'the shutter' };

export class LevelGraph {
  constructor(area, ctx) {
    this.area = area;
    this.ctx = ctx; // { links: Map spaceId → [{storeId, storeName}], ... }
    this.nodes = [];
    this.edges = [];
    this.splits = new Map(); // skeleton edge index → [{t, node}]
    this.rooms = new Map(); // space index → { doors: [{x, z, node, w, kind, explicit}], links: [{door, other}] }
    this.seeds = [];
    this.exits = [];
    this.places = [];
    this.openingPlaces = [];
    this.notes = []; // problems found while joining (stops off the walkway)
    const sk = skeleton(area);
    this.sk = sk;
    for (const n of sk.nodes) this.node(n.x, n.z);
    this.skEdges = sk.edges.map((e) => ({ ...e }));
  }

  node(x, z, flags = {}) {
    const { grid, out } = this.area;
    const idx = grid.at(x, z);
    this.nodes.push({ x, z, out: flags.out ?? (idx >= 0 && out[idx] === 1), inner: !!flags.inner, label: flags.label ?? null });
    return this.nodes.length - 1;
  }

  edge(a, b, meta = {}) {
    if (a === b) return;
    this.edges.push({ a, b, kind: meta.kind ?? 'walk', w: meta.w ?? null, through: meta.through ?? null, floor: !!meta.floor, label: meta.label ?? null, oneWay: !!meta.oneWay });
  }

  /** Cells people may cross to reach the network: walkable or under a blocking feature, never a wall. */
  canCross(idx) {
    const { walk, featureBlock, wallId } = this.area;
    return wallId[idx] < 0 && (walk[idx] === 1 || featureBlock[idx] === 1);
  }

  /**
   * Joins node [n] (at its x, z) to the walkway network. Returns false when no
   * walkway is within reach (the node is then left on its own).
   */
  attach(n) {
    const { grid } = this.area;
    const { x, z } = this.nodes[n];
    const start = grid.at(x, z);
    if (start < 0 || !this.sk.edges.length) return false;
    const { cellChain } = this.sk;
    const maxCells = Math.ceil(ATTACH_REACH / grid.cell);
    const seen = new Map([[start, -1]]);
    const queue = [start];
    let found = -1;
    const { gw, gh } = grid;
    for (let qi = 0; qi < queue.length && found < 0; qi++) {
      const c = queue[qi];
      if (cellChain[c] >= 0) {
        found = c;
        break;
      }
      const i = c % gw;
      const j = Math.floor(c / gw);
      for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]) {
        const ni = i + di;
        const nj = j + dj;
        if (ni < 0 || nj < 0 || ni >= gw || nj >= gh) continue;
        if (Math.abs(ni - (start % gw)) > maxCells || Math.abs(nj - Math.floor(start / gw)) > maxCells) continue;
        const y = nj * gw + ni;
        if (seen.has(y) || !this.canCross(y)) continue;
        seen.set(y, c);
        queue.push(y);
      }
    }
    if (found < 0) return false;

    // Nearest point on the chain's straight runs.
    const chain = cellChain[found];
    let best = null;
    for (const ei of this.sk.chainEdges[chain]) {
      const e = this.skEdges[ei];
      const A = this.nodes[e.a];
      const B = this.nodes[e.b];
      const dx = B.x - A.x;
      const dz = B.z - A.z;
      const len2 = dx * dx + dz * dz || 1e-12;
      const t = Math.max(0, Math.min(1, ((x - A.x) * dx + (z - A.z) * dz) / len2));
      const px = A.x + t * dx;
      const pz = A.z + t * dz;
      const d = Math.hypot(px - x, pz - z);
      if (!best || d < best.d - 1e-9) best = { ei, t, px, pz, d, len: Math.sqrt(len2) };
    }
    if (!best) return false;
    let target;
    const e = this.skEdges[best.ei];
    if (best.t * best.len < 0.15) target = e.a;
    else if ((1 - best.t) * best.len < 0.15) target = e.b;
    else {
      target = this.node(best.px, best.pz);
      if (!this.splits.has(best.ei)) this.splits.set(best.ei, []);
      this.splits.get(best.ei).push({ t: best.t, node: target });
    }
    // The way to the network crosses the walkway it joins, so it is as wide as that walkway
    // (the width at the starting point itself is low: doors and stops sit against walls).
    const w = e.w;
    const T = this.nodes[target];
    if (lineOk(grid, x, z, T.x, T.z, (i) => this.canCross(i))) {
      this.edge(n, target, { w });
      return true;
    }
    // Around a corner: follow the search path back, straightened.
    const path = [];
    for (let c = found; c >= 0; c = seen.get(c)) path.push(grid.center(c));
    path.reverse();
    const simple = simplifyLine([[x, z], ...path.slice(1, -1), [T.x, T.z]], 0.2);
    let prev = n;
    for (let k = 1; k < simple.length - 1; k++) {
      const m = this.node(simple[k][0], simple[k][1]);
      this.edge(prev, m, { w });
      prev = m;
    }
    this.edge(prev, target, { w });
    return true;
  }

  /** Replaces split skeleton edges by their pieces, and adds the network edges. */
  materialise() {
    this.skEdges.forEach((e, ei) => {
      const cuts = (this.splits.get(ei) ?? []).sort((p, q) => p.t - q.t || p.node - q.node);
      let prev = e.a;
      for (const c of cuts) {
        this.edge(prev, c.node, { w: e.w });
        prev = c.node;
      }
      this.edge(prev, e.b, { w: e.w });
    });
  }

  room(k) {
    if (!this.rooms.has(k)) this.rooms.set(k, { doors: [], links: [] });
    return this.rooms.get(k);
  }

  /** What lies along [n] from point (x, z): a walkway, a room, the outside, a wall, or nothing within 1.5 m. */
  probe(x, z, nx, nz, from, host) {
    const { grid, walk, spaceId, wallId, inOutline, featureBlock } = this.area;
    const step = grid.cell * 0.5;
    for (let d = from; d <= from + 1.5; d += step) {
      const px = x + nx * d;
      const pz = z + nz * d;
      const idx = grid.at(px, pz);
      if (idx < 0) return { kind: 'outside', x: px, z: pz, idx };
      if (wallId[idx] >= 0 && wallId[idx] !== host) return { kind: 'blocked' };
      if (wallId[idx] === host || featureBlock[idx]) continue;
      if (walk[idx]) return { kind: 'region', x: grid.cx(idx % grid.gw), z: grid.cz(Math.floor(idx / grid.gw)), idx };
      if (spaceId[idx] >= 0) return { kind: 'room', space: spaceId[idx] };
      if (!inOutline[idx]) return { kind: 'outside', x: px, z: pz, idx };
    }
    return { kind: 'none' };
  }

  /** Doors in walls (openings): each joins the two sides of its host wall. */
  joinOpenings() {
    const level = this.area.level;
    const walls = level.walls ?? [];
    const wallIndex = new Map(walls.map((w, k) => [w.id, k]));
    const openings = [...(level.openings ?? [])].sort((a, b) => (a.id < b.id ? -1 : 1));
    for (const o of openings) {
      if (o.kind === 'window') continue;
      const host = wallIndex.get(o.wall);
      if (host === undefined) continue;
      const w = walls[host];
      const dx = w.b[0] - w.a[0];
      const dz = w.b[1] - w.a[1];
      const len = Math.hypot(dx, dz) || 1;
      const cx = w.a[0] + dx * o.at;
      const cz = w.a[1] + dz * o.at;
      const nx = -dz / len;
      const nz = dx / len;
      const from = (w.t ?? 0.2) / 2 + this.area.grid.cell;
      const sides = [this.probe(cx, cz, nx, nz, from, host), this.probe(cx, cz, -nx, -nz, from, host)];
      const label = o.label?.trim() || OPENING_LABEL[o.kind] || 'the door';
      const isOutside = (s) => s.kind === 'outside' || (s.kind === 'region' && this.area.out[s.idx] === 1 && !this.area.inOutline[s.idx]);
      const width = o.w ?? 1.2;
      const kinds = sides.map((s) => s.kind);
      const D = this.node(cx, cz, { label: o.label?.trim() || null });
      const door = { x: cx, z: cz, node: D, w: width, kind: o.kind, explicit: true, opening: o.id };
      let seeded = false;
      const outIdx = sides.findIndex(isOutside);
      if (outIdx >= 0 && sides[1 - outIdx].kind !== 'outside') {
        // Indoors ↔ outdoors: an "enter" edge, named for directions.
        const inSide = sides[1 - outIdx];
        const sgn = outIdx === 0 ? 1 : -1;
        const O = this.node(cx + sgn * nx * (from + 0.5), cz + sgn * nz * (from + 0.5), { out: true, label });
        this.nodes[D].label = label;
        this.edge(D, O, { kind: 'enter', w: width, label });
        const oSide = sides[outIdx];
        if (oSide.kind === 'region') this.attach(O);
        if (inSide.kind === 'region') {
          const I = this.node(inSide.x, inSide.z);
          this.edge(I, D, { w: width });
          this.attach(I);
        } else if (inSide.kind === 'room') {
          this.room(inSide.space).doors.push(door);
        }
        if (o.kind === 'entrance') {
          this.seeds.push(D, O);
          seeded = true;
          if (w.kind === 'boundary') {
            this.exits.push({ id: o.id, name: o.label?.trim() || null, node: O });
            // A way in and out shoppers can look up (docs/shopper-package-format.md §3, places).
            this.openingPlaces.push({ id: o.id, name: o.label?.trim() || 'Entrance', at: [cx, cz], node: D });
          }
        }
      } else {
        for (const s of sides) {
          if (s.kind === 'region') {
            const P = this.node(s.x, s.z);
            this.edge(D, P, { w: width });
            this.attach(P);
          } else if (s.kind === 'room') {
            this.room(s.space).doors.push(door);
          }
        }
        if (kinds[0] === 'room' && kinds[1] === 'room' && sides[0].space !== sides[1].space) {
          this.room(sides[0].space).links.push({ door: D, other: sides[1].space });
          this.room(sides[1].space).links.push({ door: D, other: sides[0].space });
        }
      }
      if (o.kind === 'entrance' && !seeded) this.seeds.push(D);
    }
  }

  /** Rooms with no opening of their own: their open edges onto a walkway become doors (at most 4, each ≥ 0.8 m). */
  virtualDoors() {
    const { grid, walk, spaceId, wallId, featureBlock } = this.area;
    const spaces = this.area.spaces;
    spaces.forEach((s, k) => {
      if (isWalkableSpace(s)) return;
      if ((this.rooms.get(k)?.doors ?? []).some((d) => d.explicit)) return;
      const ring = s.shape.outer;
      const samples = [];
      let perimeter = 0;
      for (let e = 0; e < ring.length; e++) perimeter += Math.hypot(ring[(e + 1) % ring.length][0] - ring[e][0], ring[(e + 1) % ring.length][1] - ring[e][1]);
      const step = Math.max(VIRTUAL_STEP, perimeter / 2000);
      for (let e = 0; e < ring.length; e++) {
        const [x0, z0] = ring[e];
        const [x1, z1] = ring[(e + 1) % ring.length];
        const len = Math.hypot(x1 - x0, z1 - z0);
        if (len < 1e-6) continue;
        const ux = (x1 - x0) / len;
        const uz = (z1 - z0) / len;
        let nx = -uz;
        let nz = ux;
        const mx = (x0 + x1) / 2;
        const mz = (z0 + z1) / 2;
        if (inPolygon([mx + nx * 0.05, mz + nz * 0.05], s.shape)) {
          nx = -nx;
          nz = -nz;
        }
        for (let d = step / 2; d < len; d += step) {
          const px = x0 + ux * d;
          const pz = z0 + uz * d;
          let open = null;
          for (let r = 0.05; r <= VIRTUAL_REACH; r += grid.cell * 0.5) {
            const idx = grid.at(px + nx * r, pz + nz * r);
            if (idx < 0 || wallId[idx] >= 0) break;
            if (featureBlock[idx]) continue;
            if (walk[idx]) {
              open = idx;
              break;
            }
            if (spaceId[idx] >= 0 && spaceId[idx] !== k) break;
          }
          samples.push({ x: px, z: pz, open });
        }
      }
      if (!samples.length) return;
      // Stretches of open samples, cyclic.
      const firstClosed = samples.findIndex((p) => p.open === null);
      const stretches = [];
      if (firstClosed < 0) stretches.push(samples);
      else {
        let cur = [];
        for (let q = 1; q <= samples.length; q++) {
          const p = samples[(firstClosed + q) % samples.length];
          if (p.open === null) {
            if (cur.length) stretches.push(cur);
            cur = [];
          } else cur.push(p);
        }
        if (cur.length) stretches.push(cur);
      }
      const doors = stretches
        .map((st) => ({ st, len: st.length * step }))
        .filter((x) => x.len >= MIN_DOOR)
        .sort((a, b) => b.len - a.len)
        .slice(0, 4);
      for (const { st, len } of doors) {
        const mid = st[Math.floor(st.length / 2)];
        const D = this.node(mid.x, mid.z);
        const P = this.node(grid.cx(mid.open % grid.gw), grid.cz(Math.floor(mid.open / grid.gw)));
        const w = Math.min(len, 4);
        this.edge(D, P, { w });
        this.attach(P);
        this.room(k).doors.push({ x: mid.x, z: mid.z, node: D, w, kind: 'door', explicit: false });
      }
    });
  }

  /** Inside a room: room-to-room doors join that room's other doors; stores with two or more doors get cut-throughs. */
  roomInsides() {
    const { grid, spaceId, wallId } = this.area;
    const spaces = this.area.spaces;
    for (const [k, r] of [...this.rooms.entries()].sort((a, b) => a[0] - b[0])) {
      const s = spaces[k];
      const inRoom = (i) => spaceId[i] === k && wallId[i] < 0;
      // Room-to-room doors: walk across this room to its other doors (marked as crossing it).
      for (const link of r.links) {
        for (const d of r.doors) {
          if (d.node === link.door) continue;
          this.edge(link.door, d.node, { w: d.w, through: s.id });
        }
      }
      const linked = this.ctx.links.get(s.id);
      const explicit = r.doors.filter((d) => d.explicit && !r.links.some((l) => l.door === d.node));
      if (!(linked?.length || s.type === 'anchor') || explicit.length < 2) continue;
      const far = explicit.some((a, i) => explicit.some((b, j) => j > i && Math.hypot(a.x - b.x, a.z - b.z) >= 2));
      if (!far) continue;
      const inner = [];
      for (const d of explicit.slice(0, 8)) {
        // 1.5 m into the room, on a cell of the room.
        let best = -1;
        let bestD = Infinity;
        const c = grid.at(d.x, d.z);
        if (c < 0) continue;
        const reach = Math.ceil(2.5 / grid.cell);
        const ci = c % grid.gw;
        const cj = Math.floor(c / grid.gw);
        for (let j = Math.max(0, cj - reach); j <= Math.min(grid.gh - 1, cj + reach); j++) {
          for (let i = Math.max(0, ci - reach); i <= Math.min(grid.gw - 1, ci + reach); i++) {
            const idx = j * grid.gw + i;
            if (!inRoom(idx)) continue;
            const dd = Math.abs(Math.hypot(grid.cx(i) - d.x, grid.cz(j) - d.z) - 1.5);
            if (dd < bestD - 1e-9) {
              bestD = dd;
              best = idx;
            }
          }
        }
        if (best < 0) continue;
        const N = this.node(grid.cx(best % grid.gw), grid.cz(Math.floor(best / grid.gw)), { inner: true });
        this.edge(d.node, N, { w: d.w, through: s.id });
        inner.push(N);
      }
      for (let i = 0; i < inner.length; i++) {
        for (let j = i + 1; j < inner.length; j++) {
          const A = this.nodes[inner[i]];
          const B = this.nodes[inner[j]];
          if (lineOk(grid, A.x, A.z, B.x, B.z, inRoom)) this.edge(inner[i], inner[j], { w: 2, through: s.id, floor: true });
        }
      }
    }
  }

  /**
   * A connector stop: the nearest walkway cell within the endpoint's pad (w × len,
   * plus 1 m). Returns the node, or null when the stop is not on a walkway.
   */
  stop(ep) {
    const { grid, walk } = this.area;
    const r = Math.max(ep.w ?? 1.4, ep.len ?? 4) / 2 + 1;
    const c = grid.at(ep.x, ep.z);
    let best = -1;
    let bestD = Infinity;
    const reach = Math.ceil(r / grid.cell);
    const ci = c >= 0 ? c % grid.gw : Math.floor((ep.x - grid.minX) / grid.cell);
    const cj = c >= 0 ? Math.floor(c / grid.gw) : Math.floor((ep.z - grid.minZ) / grid.cell);
    for (let j = Math.max(0, cj - reach); j <= Math.min(grid.gh - 1, cj + reach); j++) {
      for (let i = Math.max(0, ci - reach); i <= Math.min(grid.gw - 1, ci + reach); i++) {
        const idx = j * grid.gw + i;
        if (!walk[idx]) continue;
        const d = Math.hypot(grid.cx(i) - ep.x, grid.cz(j) - ep.z);
        if (d <= r && d < bestD - 1e-9) {
          bestD = d;
          best = idx;
        }
      }
    }
    if (best < 0) return null;
    const N = walk[c] === 1 ? this.node(ep.x, ep.z) : this.node(grid.cx(best % grid.gw), grid.cz(Math.floor(best / grid.gw)));
    return this.attach(N) ? N : null;
  }

  /** A point placed on the walkway network (a place in a corridor, a feature, an exit). */
  pointNode(x, z, flags = {}) {
    const N = this.node(x, z, flags);
    return this.attach(N) ? N : N;
  }
}

/** The App category of a place (docs/shopper-package-format.md §3). */
export function spaceCategory(space, storeCategory) {
  if (storeCategory) return storeCategory;
  switch (space.type) {
    case 'food':
      return 'food';
    case 'restroom':
      return 'restroom';
    case 'parking':
      return 'parking';
    case 'service':
      return 'services';
    default:
      return 'other';
  }
}

const FEATURE_CAT = {
  restroom: 'restroom',
  atm: 'atm',
  info_desk: 'info',
  customer_service: 'info',
  concierge: 'info',
  directory_sign: 'info',
  lost_found: 'info',
  entrance: 'exit',
  exit: 'exit',
  fire_exit: 'exit',
  parking_entrance: 'parking',
};
export const featureCategory = (type) => FEATURE_CAT[type] ?? 'services';
export const isTargetFeature = (type) => FEATURE_TYPES[type]?.target === true;
export const SEED_FEATURES = new Set(['entrance', 'exit', 'parking_entrance']);
export const EXIT_FEATURES = new Set(['entrance', 'exit', 'fire_exit']);
export { CLEAR, OUTDOOR_TYPES };
