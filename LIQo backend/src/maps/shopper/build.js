// The shopper package builder (Round 21, P1-08; format in
// docs/shopper-package-format.md, agreed with the mobile session). Pure: a
// published layout and its store links in, the package and the publish
// gate's problems out. Same input, same bytes: every array is emitted in a
// stable order and every number is rounded the same way.
import crypto from 'node:crypto';
import { FEATURE_TYPES } from '../catalog.js';
import { levelArea, isWalkableSpace, OUTDOOR_TYPES } from './area.js';
import { packageLevels, levelIndex } from './levels.js';
import { LevelGraph, spaceCategory, featureCategory, isTargetFeature, SEED_FEATURES, EXIT_FEATURES } from './network.js';
import { inPolygon } from './raster.js';
import { gate } from './gate.js';

export const FORMAT_VERSION = 1;
export const MAX_BYTES = 20 * 1024 * 1024;

const rad = (deg) => ((Number(deg) || 0) * Math.PI) / 180;
const r1 = (v) => {
  const x = Math.round(v * 10) / 10;
  return Object.is(x, -0) ? 0 : x;
};
const r2 = (v) => {
  const x = Math.round(v * 100) / 100;
  return Object.is(x, -0) ? 0 : x;
};
const r3 = (v) => {
  const x = Math.round(v * 1000) / 1000;
  return Object.is(x, -0) ? 0 : x;
};
const byId = (a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/** Level-local plan point → branch frame (same as web/map3d/model.js placer). Package y = editor z. */
export function placer(building, level) {
  const lr = rad(level.rot);
  const br = rad(building.rot);
  const [ox, oz] = level.offset ?? [0, 0];
  const [bx, bz] = building.origin ?? [0, 0];
  const lc = Math.cos(lr);
  const ls = Math.sin(lr);
  const bc = Math.cos(br);
  const bs = Math.sin(br);
  return ([x, z]) => {
    const x1 = x * lc - z * ls + ox;
    const z1 = x * ls + z * lc + oz;
    return [x1 * bc - z1 * bs + bx, x1 * bs + z1 * bc + bz];
  };
}

/** A building's short name for the Layers panel ("Main Mall" → "Main"). */
const buildingShort = (name) => String(name ?? '').trim().split(/\s+/)[0]?.slice(0, 12) || 'Building';

const CONNECTOR_HOP = { elevator: 'lift', escalator: 'escalator', stairs: 'stairs', ramp: 'ramp' };
const PART = { lift: 'lift door', escalator: 'escalator end', stairs: 'stairs end', ramp: 'ramp end', walkway: 'walkway end', bridge: 'bridge end' };
const CONN_NAME = { elevator: 'A lift', escalator: 'An escalator', stairs: 'Stairs', ramp: 'A ramp', moving_walkway: 'A moving walkway', bridge: 'A bridge', walkway: 'A walkway' };

/**
 * Builds the package (without its version and time, see stampPackage).
 * @returns {{ package, problems: {code, message, ids}[], warnings: {code, message, ids}[], stats }}
 */
export function buildShopperPackage({ layout, links = [], appCategories = {}, floorLabels = [], branchId = null, branchName = null, mallName = null, previous = null, limits = {} }) {
  const buildings = [...(layout.buildings ?? [])].sort(byId);
  const levels = packageLevels({ buildings }, floorLabels);
  const lvOf = levelIndex(levels);
  const manyBuildings = buildings.length > 1;
  const levelName = (b, l) => (manyBuildings ? `${b.name}, ${l.name}` : l.name);

  const linksBySpace = new Map();
  for (const l of [...links].sort((a, b) => a.storeId - b.storeId)) {
    if (!linksBySpace.has(l.spaceKey)) linksBySpace.set(l.spaceKey, []);
    linksBySpace.get(l.spaceKey).push(l);
  }
  const connectors = [...(layout.connectors ?? [])].sort(byId).filter((c) => c.kind !== 'vehicle_ramp' && c.walkable !== false);

  // ---- Per editor level: area, network, doors, rooms, places ----
  const parts = [];
  const levelProblems = [];
  const stopNodes = new Map(); // `${connectorId}#${k}` → { part, node }
  const stopProblems = [];
  for (const b of buildings) {
    for (const l of [...(b.levels ?? [])]) {
      const pl = lvOf.get(l.id);
      const extra = [];
      for (const c of connectors) for (const ep of c.endpoints ?? []) if (ep.level === l.id) extra.push([ep.x, ep.z]);
      const area = levelArea(l, { extraPoints: extra, cellCap: limits.cellCap });
      const lg = new LevelGraph(area, { links: linksBySpace });
      lg.joinOpenings();
      lg.virtualDoors();
      lg.roomInsides();
      const part = { b, l, pl, area, lg, places: [], roomInfo: [], features: [] };
      parts.push(part);
      if (area.passableM2 < 4) levelProblems.push({ code: 'no_corridor', message: `${levelName(b, l)} has no corridor`, ids: [l.id], lv: pl.lv });

      // Spaces as places.
      (l.spaces ?? []).forEach((s, k) => {
        const linked = linksBySpace.get(s.id) ?? [];
        const storeId = linked[0]?.storeId ?? null;
        const name = String(s.name ?? '').trim();
        const walkable = isWalkableSpace(s);
        const room = lg.rooms.get(k);
        const doors = room?.doors ?? [];
        let at = centroid(s.shape.outer);
        if (!inPolygon(at, s.shape)) at = nearestCellOf(area, k, at) ?? at;
        const isPlace = storeId != null || name !== '' || s.type === 'restroom' || s.type === 'parking';
        if (!isPlace) return;
        let nodes;
        if (walkable) nodes = [lg.pointNode(at[0], at[1])];
        else nodes = doors.map((d) => d.node);
        const main = [...doors].sort((x, y) => Number(y.kind === 'entrance') - Number(x.kind === 'entrance') || y.w - x.w)[0] ?? null;
        const storeName = linked[0]?.storeName ?? null;
        part.places.push({
          id: s.id,
          storeId,
          name: name || storeName || null,
          cat: spaceCategory(s, storeId != null ? appCategories[storeId] ?? 'other' : null),
          type: s.type === 'custom' ? s.customType || 'custom' : s.type,
          kind: walkable ? (OUTDOOR_TYPES.has(s.type) ? 'zone' : 'svc') : s.type === 'anchor' || doors.filter((d) => d.explicit).length >= 2 ? 'box' : 'store',
          at,
          doors: doors.map((d) => [d.x, d.z]),
          nodes,
          door: main ? [main.x, main.z] : null,
          w: main ? main.w : null,
          shape: s.shape.outer,
          outside: walkable && OUTDOOR_TYPES.has(s.type) && !inOutlineAt(area, at),
        });
        if (!walkable) {
          const who = storeName ? `${storeName} (${name || `a ${s.type} unit on ${levelName(b, l)}`})` : name;
          const checked = storeId != null || name !== '';
          part.roomInfo.push({ k, who: who || s.id, ids: [s.id], doors: doors.map((d) => d.node), links: room?.links ?? [], checked, restroom: s.type === 'restroom' });
        }
        if (linked.length > 1) part.multiLink = (part.multiLink ?? 0) + 1;
      });

      // Entrances in outer walls as places.
      for (const op of lg.openingPlaces) {
        part.places.push({ id: op.id, storeId: null, name: op.name, cat: 'exit', type: 'entrance', kind: 'svc', at: op.at, doors: [], nodes: [op.node], door: null, w: null, exit: true });
      }

      // Target features as places; entrances and exits.
      for (const f of [...(l.features ?? [])].sort(byId)) {
        const def = FEATURE_TYPES[f.type];
        if (!def) continue;
        const cell = area.grid.at(f.x, f.z);
        const k = cell >= 0 ? area.spaceId[cell] : -1;
        const inRoom = k >= 0 && !isWalkableSpace(area.spaces[k]);
        let nodes;
        if (inRoom) nodes = (lg.rooms.get(k)?.doors ?? []).map((d) => d.node);
        else if (isTargetFeature(f.type) || SEED_FEATURES.has(f.type) || f.type === 'assembly_point') nodes = [lg.pointNode(f.x, f.z)];
        else nodes = [];
        if (SEED_FEATURES.has(f.type)) lg.seeds.push(...nodes);
        const name = String(f.label ?? '').trim() || def.label;
        if (EXIT_FEATURES.has(f.type) && nodes.length) lg.exits.push({ id: f.id, name, node: nodes[0] });
        if (f.type === 'assembly_point' && nodes.length) lg.exits.push({ id: f.id, name, node: nodes[0], assembly: true });
        if (isTargetFeature(f.type)) {
          part.places.push({ id: f.id, storeId: null, name, cat: featureCategory(f.type), type: f.type, kind: 'svc', at: [f.x, f.z], doors: [], nodes, door: null, w: null, exit: EXIT_FEATURES.has(f.type) });
        }
      }

      // Connector stops on this level.
      for (const c of connectors) {
        (c.endpoints ?? []).forEach((ep, idx) => {
          if (ep.level !== l.id) return;
          const node = lg.stop(ep);
          if (node == null) {
            const type = CONNECTOR_HOP[c.kind] ?? (c.kind === 'moving_walkway' ? 'walkway' : c.kind);
            stopProblems.push({ code: 'stop_off_walkway', message: `${c.name?.trim() || CONN_NAME[c.kind] || 'A connector'}, ${levelName(b, l)}: the ${PART[type] ?? 'end'} isn't on a walkway`, ids: [c.id], lv: pl.lv });
          } else stopNodes.set(`${c.id}#${idx}`, { part, node });
        });
      }
      lg.materialise();
    }
  }

  // ---- Into one branch-wide graph ----
  const gNodes = [];
  const gEdges = [];
  for (const part of parts) {
    const place = placer(part.b, part.l);
    part.offset = gNodes.length;
    for (const nd of part.lg.nodes) {
      const [x, y] = place([nd.x, nd.z]);
      gNodes.push({ lv: part.pl.lv, x, y, out: nd.out, inner: nd.inner, label: nd.label });
    }
    for (const e of part.lg.edges) gEdges.push({ ...e, a: e.a + part.offset, b: e.b + part.offset });
  }
  const gid = (part, n) => part.offset + n;

  // Connectors: hops between levels, bridges and walkways on one level.
  const pkgConnectors = [];
  for (const c of connectors) {
    const stops = (c.endpoints ?? [])
      .map((ep, idx) => ({ ep, idx, s: stopNodes.get(`${c.id}#${idx}`) }))
      .filter((x) => x.s)
      .map((x) => ({ idx: x.idx, lv: x.s.part.pl.lv, node: gid(x.s.part, x.s.node) }));
    if (stops.length < 2) continue;
    const ordered = c.oneWay ? stops : [...stops].sort((a, b) => a.lv - b.lv || a.idx - b.idx);
    const sameLevel = ordered.every((s) => s.lv === ordered[0].lv);
    let ctype = CONNECTOR_HOP[c.kind] ?? null;
    if (c.kind === 'moving_walkway') ctype = sameLevel ? null : 'escalator';
    if ((c.kind === 'bridge' || c.kind === 'walkway') && !sameLevel) ctype = 'ramp';
    const label = c.name?.trim() || (c.kind === 'bridge' ? 'the bridge' : c.kind === 'walkway' || c.kind === 'moving_walkway' ? 'the walkway' : null);
    const w = Math.min(...(c.endpoints ?? []).map((e) => e.w ?? 1.4));
    for (let k = 1; k < ordered.length; k++) {
      const a = ordered[k - 1];
      const b = ordered[k];
      if (ctype && a.lv !== b.lv) gEdges.push({ a: a.node, b: b.node, kind: 'hop', w, conn: c.id, ctype, oneWay: !!c.oneWay, through: null, label: null });
      else gEdges.push({ a: a.node, b: b.node, kind: ctype ? 'walk' : 'bridge', w, oneWay: !!c.oneWay, through: null, label: ctype ? null : label });
    }
    if (ctype) {
      const firstBuilding = buildings.find((bb) => (bb.levels ?? []).some((l) => l.id === c.endpoints[0].level));
      pkgConnectors.push({ id: c.id, type: ctype, name: c.name?.trim() || null, stops: ordered.map((s) => ({ lv: s.lv, node: s.node })), oneWay: !!c.oneWay, building: firstBuilding?.id ?? null });
    }
  }

  // ---- Snap to 0.1 m, merge equal points (the phone keys nodes that way), number in order ----
  const keyOf = (nd) => `${nd.lv}|${r1(nd.x)}|${r1(nd.y)}`;
  const rep = new Map();
  const merged = [];
  const mapTo = new Int32Array(gNodes.length);
  gNodes.forEach((nd, i) => {
    const key = keyOf(nd);
    if (!rep.has(key)) {
      rep.set(key, merged.length);
      merged.push({ lv: nd.lv, x: r1(nd.x), y: r1(nd.y), out: nd.out, inner: nd.inner, label: nd.label });
    } else {
      const m = merged[rep.get(key)];
      m.out = m.out || nd.out;
      m.inner = m.inner && nd.inner;
      m.label = m.label ?? nd.label;
    }
    mapTo[i] = rep.get(key);
  });
  const order = merged.map((_, i) => i).sort((a, b) => merged[a].lv - merged[b].lv || merged[a].y - merged[b].y || merged[a].x - merged[b].x);
  const finalIdx = new Int32Array(merged.length);
  order.forEach((m, k) => (finalIdx[m] = k));
  const nodeIdx = (globalIdx) => finalIdx[mapTo[globalIdx]];
  const nodes = order.map((m) => merged[m]);

  const edgeMap = new Map();
  for (const e of gEdges) {
    let a = nodeIdx(e.a);
    let b = nodeIdx(e.b);
    if (a === b) continue;
    if (!e.oneWay && a > b) [a, b] = [b, a];
    const key = `${a}|${b}|${e.kind}|${e.through ?? ''}|${e.conn ?? ''}|${e.oneWay ? 1 : 0}`;
    const len = e.kind === 'hop' ? 0 : Math.hypot(nodes[a].x - nodes[b].x, nodes[a].y - nodes[b].y);
    const cost = e.kind === 'hop' ? null : e.floor ? 1.25 * len : len;
    const prev = edgeMap.get(key);
    if (prev && prev.cost != null && cost != null && prev.cost <= cost) continue;
    edgeMap.set(key, { a, b, kind: e.kind, len, cost, w: e.w ?? 1.2, oneWay: !!e.oneWay, through: e.through ?? null, conn: e.conn ?? null, ctype: e.ctype ?? null, label: e.label ?? null });
  }
  const edges = [...edgeMap.values()].sort((x, y) => x.a - y.a || x.b - y.b || x.kind.localeCompare(y.kind) || String(x.through ?? '').localeCompare(String(y.through ?? '')) || String(x.conn ?? '').localeCompare(String(y.conn ?? '')));

  // ---- Places, exits, connectors in the final numbering ----
  const places = [];
  const roomList = [];
  const roomKey = new Map();
  for (const part of parts) {
    const place = placer(part.b, part.l);
    const P = (p) => {
      const [x, y] = place(p);
      return [r2(x), r2(y)];
    };
    for (const p of part.places) {
      const pts = p.shape ? p.shape.map(P) : [P(p.at)];
      const xs = pts.map((q) => q[0]);
      const ys = pts.map((q) => q[1]);
      const nodesOut = [...new Set(p.nodes.map((n) => `n${nodeIdx(gid(part, n))}`))];
      const out = { id: p.id };
      if (p.storeId != null) out.storeId = p.storeId;
      out.lv = part.pl.lv;
      if (p.name) out.name = p.name;
      out.cat = p.cat;
      out.type = p.type;
      out.kind = p.kind;
      out.at = P(p.at);
      out.doors = p.doors.map(P);
      out.nodes = nodesOut;
      out.wing = p.outside ? 'O' : part.b.id;
      if (p.shape) out.rect = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
      if (p.door) out.door = P(p.door);
      if (p.w != null) out.w = r1(p.w);
      if (p.exit) out.exit = true;
      places.push(out);
    }
    for (const r of part.roomInfo) {
      roomKey.set(`${part.l.id}#${r.k}`, roomList.length);
      roomList.push({ ...r, part, lv: part.pl.lv });
    }
  }
  places.sort(byId);
  const rooms = roomList.map((r) => ({
    who: r.who,
    ids: r.ids,
    lv: r.lv,
    checked: r.checked,
    doors: r.doors.map((n) => nodeIdx(gid(r.part, n))),
    linkDoors: r.links.map((lk) => nodeIdx(gid(r.part, lk.door))),
    links: r.links.map((lk) => roomKey.get(`${r.part.l.id}#${lk.other}`)).filter((x) => x !== undefined),
  }));
  const unconnected = roomList
    .filter((r) => !r.checked && r.restroom && !r.doors.length)
    .map((r) => ({ code: 'place_no_door', message: `A restroom on ${r.part.l.name} has no door to a corridor; directions will end at the nearest corridor.`, ids: r.ids }));
  if (parts.some((p) => p.multiLink)) unconnected.push({ code: 'link_multiple', message: 'A space is linked to more than one store; the phone shows the first one there.', ids: [] });

  const exits = [];
  const seeds = [];
  for (const part of parts) {
    for (const e of part.lg.exits) {
      const ex = { id: e.id };
      if (e.name) ex.name = e.name;
      ex.node = `n${nodeIdx(gid(part, e.node))}`;
      if (e.assembly) ex.assembly = true;
      exits.push(ex);
    }
    for (const s of part.lg.seeds) seeds.push(nodeIdx(gid(part, s)));
  }
  exits.sort(byId);
  pkgConnectors.sort(byId);
  const connectorsOut = pkgConnectors.map((c) => {
    const out = { id: c.id, type: c.type };
    if (c.name) out.name = c.name;
    out.stops = c.stops.map((s) => ({ lv: s.lv, node: `n${nodeIdx(s.node)}` }));
    if (c.oneWay) out.oneWay = true;
    if (c.building) out.building = c.building;
    return out;
  });

  // ---- Drawing ----
  const drawing = drawLayout(buildings, levels, lvOf, linksBySpace);

  const graph = {
    nodes: nodes.map((nd, i) => {
      const o = { id: `n${i}`, lv: nd.lv, x: nd.x, y: nd.y };
      if (nd.out) o.out = true;
      if (nd.inner) o.inner = true;
      if (nd.label) o.label = nd.label;
      return o;
    }),
    edges: edges.map((e) => {
      const o = { a: `n${e.a}`, b: `n${e.b}`, kind: e.kind, len: r3(e.len), cost: e.cost == null ? null : r3(e.cost), w: r1(e.w) };
      if (e.oneWay) o.oneWay = true;
      if (e.through != null) o.through = e.through;
      if (e.conn) o.conn = e.conn;
      if (e.ctype) o.ctype = e.ctype;
      if (e.label) o.label = e.label;
      return o;
    }),
  };

  const pkg = {
    formatVersion: FORMAT_VERSION,
    branchId,
    branchName,
    mallName,
    version: 0,
    publishedAt: null,
    units: 'm',
    levels: drawing.levels,
    spaces: drawing.spaces,
    walls: drawing.walls,
    openings: drawing.openings,
    features: drawing.features,
    graph,
    places,
    connectors: connectorsOut,
    exits,
    buildings: drawing.buildings,
    bounds: drawing.bounds,
  };

  const levelsForGate = levels.map((l) => ({ lv: l.lv, name: manyBuildings ? `${l.editorLevels[0].building.name}, ${l.name}` : l.name, ids: l.editorLevels.map((e) => e.level.id) }));
  const gateGraph = { nodes, edges };
  const { problems, warnings } = gate(gateGraph, { seeds: [...new Set(seeds)].sort((a, b) => a - b), levels: levelsForGate, levelProblems, stopProblems, rooms, previous, places, unconnected });
  const json = JSON.stringify(pkg);
  const sizeBytes = Buffer.byteLength(json);
  const maxBytes = limits.maxBytes ?? MAX_BYTES;
  if (sizeBytes > maxBytes) {
    problems.push({ code: 'too_big', message: `The map is too big for phones to download: ${(sizeBytes / 1024 / 1024).toFixed(1)} MB, and the limit is ${Math.round(maxBytes / 1024 / 1024)} MB. Remove levels or detail you don't need.`, ids: [] });
  }
  return { package: pkg, problems, warnings, stats: { nodes: graph.nodes.length, edges: graph.edges.length, places: places.length, sizeBytes } };
}

/** Adds the version and publish time, and serialises: { json, sizeBytes, checksum } (SHA-256 of the bytes). */
export function stampPackage(pkg, { version, publishedAt }) {
  const json = JSON.stringify({ ...pkg, version, publishedAt });
  return { json, sizeBytes: Buffer.byteLength(json), checksum: crypto.createHash('sha256').update(json).digest('hex') };
}

function centroid(ring) {
  let a = 0;
  let cx = 0;
  let cz = 0;
  for (let k = 0; k < ring.length; k++) {
    const [x1, z1] = ring[k];
    const [x2, z2] = ring[(k + 1) % ring.length];
    const f = x1 * z2 - x2 * z1;
    a += f;
    cx += (x1 + x2) * f;
    cz += (z1 + z2) * f;
  }
  if (Math.abs(a) < 1e-9) return ring[0];
  return [cx / (3 * a), cz / (3 * a)];
}

function nearestCellOf(area, k, [x, z]) {
  const { grid, spaceId } = area;
  let best = null;
  let bestD = Infinity;
  for (let i = 0; i < grid.size; i++) {
    if (spaceId[i] !== k) continue;
    const [cx, cz] = grid.center(i);
    const d = Math.hypot(cx - x, cz - z);
    if (d < bestD) {
      bestD = d;
      best = [cx, cz];
    }
  }
  return best;
}

function inOutlineAt(area, [x, z]) {
  const idx = area.grid.at(x, z);
  return idx >= 0 && area.inOutline[idx] === 1;
}

/** Everything the phone draws, in the branch frame, in a stable order. */
function drawLayout(buildings, levels, lvOf, linksBySpace) {
  const spaces = [];
  const walls = [];
  const openings = [];
  const features = [];
  const outlines = new Map(levels.map((l) => [l.lv, []]));
  const buildingsOut = [];
  let all = null;
  const grow = (box, [x, y]) => (box ? [Math.min(box[0], x), Math.min(box[1], y), Math.max(box[2], x), Math.max(box[3], y)] : [x, y, x, y]);
  for (const b of buildings) {
    let bbox = null;
    const lvs = new Set();
    for (const l of [...(b.levels ?? [])].sort(byId)) {
      const lv = lvOf.get(l.id).lv;
      lvs.add(lv);
      const place = placer(b, l);
      const P = (p) => {
        const [x, y] = place(p);
        return [r2(x), r2(y)];
      };
      if (l.outline) {
        const outer = l.outline.outer.map(P);
        for (const p of outer) bbox = grow(bbox, p);
        outlines.get(lv).push({ building: b.id, outer, holes: (l.outline.holes ?? []).map((h) => h.map(P)) });
      }
      for (const s of [...(l.spaces ?? [])].sort(byId)) {
        const shape = s.shape.outer.map(P);
        for (const p of shape) bbox = grow(bbox, p);
        const out = { id: s.id, lv };
        if (s.name?.trim()) out.name = s.name.trim();
        out.type = s.type === 'custom' ? s.customType || 'custom' : s.type;
        out.shape = shape;
        const link = linksBySpace.get(s.id)?.[0];
        if (link) out.storeId = link.storeId;
        if (isWalkableSpace(s)) out.walkable = true;
        if (OUTDOOR_TYPES.has(s.type)) out.outdoor = true;
        out.label = P(labelPoint(s.shape));
        spaces.push(out);
      }
      const wallById = new Map((l.walls ?? []).map((w) => [w.id, w]));
      for (const w of [...(l.walls ?? [])].sort(byId)) {
        const a = P(w.a);
        const bb = P(w.b);
        bbox = grow(grow(bbox, a), bb);
        walls.push({ lv, a, b: bb, t: r2(w.t ?? 0.2), kind: w.kind ?? 'solid' });
      }
      for (const o of [...(l.openings ?? [])].sort(byId)) {
        const w = wallById.get(o.wall);
        if (!w) continue;
        const c = [w.a[0] + (w.b[0] - w.a[0]) * o.at, w.a[1] + (w.b[1] - w.a[1]) * o.at];
        const A = place(w.a);
        const B = place(w.b);
        const out = { id: o.id, lv, kind: o.kind, at: P(c), w: r2(o.w ?? 1.2), angle: r3(Math.atan2(B[1] - A[1], B[0] - A[0])) };
        if (o.kind === 'window') out.walkable = false;
        openings.push(out);
      }
      for (const f of [...(l.features ?? [])].sort(byId)) {
        const out = { id: f.id, lv, type: f.type, at: P([f.x, f.z]) };
        if (f.label?.trim()) out.label = f.label.trim();
        features.push(out);
      }
    }
    if (bbox) all = all ? [Math.min(all[0], bbox[0]), Math.min(all[1], bbox[1]), Math.max(all[2], bbox[2]), Math.max(all[3], bbox[3])] : bbox;
    buildingsOut.push({ id: b.id, name: b.name, short: buildingShort(b.name), levels: [...lvs].sort((x, y) => x - y), bounds: bbox ?? [0, 0, 0, 0] });
  }
  spaces.sort(byId);
  openings.sort(byId);
  features.sort(byId);
  walls.sort((x, y) => x.lv - y.lv || x.a[0] - y.a[0] || x.a[1] - y.a[1] || x.b[0] - y.b[0] || x.b[1] - y.b[1]);
  const levelsOut = levels.map((l) => {
    const out = { id: l.id, name: l.name, short: l.short, elev: r2(l.elevation), height: r2(l.height) };
    if (l.ground) out.ground = true;
    out.outlines = outlines.get(l.lv).sort((x, y) => (x.building < y.building ? -1 : 1));
    return out;
  });
  return { levels: levelsOut, spaces, walls, openings, features, buildings: buildingsOut, bounds: all ?? [0, 0, 0, 0] };
}

/** Where a space's name is drawn: its centroid when inside, else a point inside. */
function labelPoint(shape) {
  const c = centroid(shape.outer);
  if (inPolygon(c, shape)) return c;
  const [a, b, d] = shape.outer;
  return [(a[0] + b[0] + d[0]) / 3, (a[1] + b[1] + d[1]) / 3];
}
