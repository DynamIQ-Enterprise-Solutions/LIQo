// Pure validator for the LIQo branch map document. No DB, no clock, no network.
//
// Returns { layout, problems, publishProblems }:
//   layout          canonical copy: only known fields survive, numbers rounded to 1 mm
//   problems        structural errors — block every save
//   publishProblems completeness errors — block publishing only (drafts may be unfinished)
//
// Conventions (mirrored in the editor and the renderer):
//   units metres; x across, z down the plan; y derived from level elevation
//   one branch-wide grid; a building has origin [x,z] + rot; a level may add offset + rot
//   rot is degrees clockwise on the plan, normalised to [0, 360)

import { FEATURE_TYPES, SPACE_TYPES, WALL_KINDS, OPENING_KINDS, CONNECTOR_KINDS, ONE_WAY_CAPABLE, CATALOG_VERSION } from './catalog.js';
import { ID_PATTERN } from './ids.js';

export const LIMITS = Object.freeze({
  bytes: 8 * 1024 * 1024,
  buildings: 20,
  levelsPerBuilding: 30,
  pointsPerPolygon: 500,
  holesPerPolygon: 50,
  wallsPerLevel: 5000,
  openingsPerLevel: 5000,
  spacesPerLevel: 2000,
  featuresPerLevel: 10000,
  connectors: 500,
  endpointsPerConnector: 20,
  maxProblems: 50,
  coord: 5000,
});

const r3 = (n) => Math.round(n * 1000) / 1000;
const normRot = (n) => {
  const v = ((n % 360) + 360) % 360;
  return r3(v === 360 ? 0 : v);
};
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const isStr = (v) => typeof v === 'string';

class Collector {
  constructor() {
    this.problems = [];
    this.publishProblems = [];
  }
  err(path, msg) {
    if (this.problems.length < LIMITS.maxProblems) this.problems.push(`${path}: ${msg}`);
  }
  pub(path, msg) {
    if (this.publishProblems.length < LIMITS.maxProblems) this.publishProblems.push(`${path}: ${msg}`);
  }
}

function point(c, path, v) {
  if (!Array.isArray(v) || v.length !== 2 || !isNum(v[0]) || !isNum(v[1])) {
    c.err(path, 'must be [x, z]');
    return [0, 0];
  }
  if (Math.abs(v[0]) > LIMITS.coord || Math.abs(v[1]) > LIMITS.coord) c.err(path, `coordinates must stay within ±${LIMITS.coord} m`);
  return [r3(v[0]), r3(v[1])];
}

function ring(c, path, v, { min = 3 } = {}) {
  if (!Array.isArray(v)) {
    c.err(path, 'must be a list of points');
    return [];
  }
  if (v.length < min) c.err(path, `needs at least ${min} points`);
  if (v.length > LIMITS.pointsPerPolygon) c.err(path, `too many points (max ${LIMITS.pointsPerPolygon})`);
  return v.slice(0, LIMITS.pointsPerPolygon).map((p, i) => point(c, `${path}[${i}]`, p));
}

export function polygonArea(pts) {
  let a = 0;
  for (let i = 0; i < pts.length; i += 1) {
    const [x1, z1] = pts[i];
    const [x2, z2] = pts[(i + 1) % pts.length];
    a += x1 * z2 - x2 * z1;
  }
  return Math.abs(a) / 2;
}

function polygon(c, path, v, { required = true, minArea = 0.1 } = {}) {
  if (v == null) {
    if (required) c.err(path, 'is required');
    return null;
  }
  if (typeof v !== 'object') {
    c.err(path, 'must be { outer, holes }');
    return null;
  }
  const outer = ring(c, `${path}.outer`, v.outer);
  const holes = [];
  if (v.holes != null) {
    if (!Array.isArray(v.holes)) c.err(`${path}.holes`, 'must be a list of rings');
    else {
      if (v.holes.length > LIMITS.holesPerPolygon) c.err(`${path}.holes`, `too many holes (max ${LIMITS.holesPerPolygon})`);
      v.holes.slice(0, LIMITS.holesPerPolygon).forEach((h, i) => holes.push(ring(c, `${path}.holes[${i}]`, h)));
    }
  }
  if (outer.length >= 3 && polygonArea(outer) < minArea) c.err(`${path}.outer`, `area must be at least ${minArea} m²`);
  return { outer, holes };
}

function text(c, path, v, { max, required = false, def = '' } = {}) {
  if (v == null || v === '') {
    if (required) c.err(path, 'is required');
    return def;
  }
  if (!isStr(v)) {
    c.err(path, 'must be text');
    return def;
  }
  const t = v.trim();
  if (max && t.length > max) c.err(path, `must be at most ${max} characters`);
  return t.slice(0, max || t.length);
}

function num(c, path, v, { min, max, def }) {
  if (v == null) {
    if (def === undefined) c.err(path, 'is required');
    return def ?? 0;
  }
  if (!isNum(v)) {
    c.err(path, 'must be a number');
    return def ?? 0;
  }
  if (min != null && v < min) c.err(path, `must be at least ${min}`);
  if (max != null && v > max) c.err(path, `must be at most ${max}`);
  return r3(v);
}

function oneOf(c, path, v, list, def) {
  if (v == null) return def;
  if (!list.includes(v)) {
    c.err(path, `must be one of ${list.join(', ')}`);
    return def;
  }
  return v;
}

function plainProps(c, path, v) {
  if (v == null) return {};
  if (typeof v !== 'object' || Array.isArray(v)) {
    c.err(path, 'must be an object');
    return {};
  }
  const out = {};
  let n = 0;
  for (const [k, val] of Object.entries(v)) {
    if (n >= 40) break;
    if (!/^[A-Za-z0-9_]{1,40}$/.test(k)) continue;
    if (isStr(val)) out[k] = val.slice(0, 500);
    else if (isNum(val)) out[k] = r3(val);
    else if (typeof val === 'boolean') out[k] = val;
    n += 1;
  }
  return out;
}

export function validateLayout(input) {
  const c = new Collector();
  const ids = new Set();
  const takeId = (path, v, prefix) => {
    if (!isStr(v) || !ID_PATTERN.test(v)) {
      c.err(path, 'id must be 1–40 letters, digits, - or _');
      return `${prefix}-invalid`;
    }
    if (ids.has(v)) c.err(path, `duplicate id "${v}"`);
    ids.add(v);
    return v;
  };

  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    c.err('layout', 'must be an object');
    return { layout: null, problems: c.problems, publishProblems: [] };
  }

  const serialized = JSON.stringify(input);
  if (serialized.length > LIMITS.bytes) c.err('layout', `document is too large (max ${LIMITS.bytes / 1024 / 1024} MB)`);

  if (input.spec !== 1) c.err('spec', 'must be 1');
  if (input.units != null && input.units !== 'm') c.err('units', 'must be "m"');
  const catalog = input.catalog == null ? CATALOG_VERSION : input.catalog;
  if (!Number.isInteger(catalog) || catalog < 1 || catalog > CATALOG_VERSION) c.err('catalog', `must be 1–${CATALOG_VERSION}`);

  const levelIds = new Set();
  const levelsOfConnectorNeed = [];

  // ---- Buildings ----
  const buildings = [];
  if (!Array.isArray(input.buildings) || input.buildings.length === 0) c.err('buildings', 'needs at least one building');
  else if (input.buildings.length > LIMITS.buildings) c.err('buildings', `too many buildings (max ${LIMITS.buildings})`);

  for (const [bi, b] of (Array.isArray(input.buildings) ? input.buildings : []).slice(0, LIMITS.buildings).entries()) {
    const bp = `buildings[${bi}]`;
    if (!b || typeof b !== 'object') {
      c.err(bp, 'must be an object');
      continue;
    }
    const out = {
      id: takeId(`${bp}.id`, b.id, 'bd'),
      name: text(c, `${bp}.name`, b.name, { max: 80, required: true, def: 'Building' }),
      origin: point(c, `${bp}.origin`, b.origin ?? [0, 0]),
      rot: normRot(num(c, `${bp}.rot`, b.rot, { def: 0 })),
      levels: [],
    };

    if (!Array.isArray(b.levels) || b.levels.length === 0) c.pub(`${bp}.levels`, 'building has no levels');
    else if (b.levels.length > LIMITS.levelsPerBuilding) c.err(`${bp}.levels`, `too many levels (max ${LIMITS.levelsPerBuilding})`);

    for (const [li, l] of (Array.isArray(b.levels) ? b.levels : []).slice(0, LIMITS.levelsPerBuilding).entries()) {
      const lp = `${bp}.levels[${li}]`;
      if (!l || typeof l !== 'object') {
        c.err(lp, 'must be an object');
        continue;
      }
      const level = {
        id: takeId(`${lp}.id`, l.id, 'lv'),
        name: text(c, `${lp}.name`, l.name, { max: 60, required: true, def: 'Level' }),
        elevation: num(c, `${lp}.elevation`, l.elevation, { min: -50, max: 500, def: 0 }),
        height: num(c, `${lp}.height`, l.height, { min: 2, max: 30, def: 4 }),
        offset: point(c, `${lp}.offset`, l.offset ?? [0, 0]),
        rot: normRot(num(c, `${lp}.rot`, l.rot, { def: 0 })),
        outline: polygon(c, `${lp}.outline`, l.outline, { required: false, minArea: 1 }),
        walls: [],
        openings: [],
        spaces: [],
        features: [],
      };
      levelIds.add(level.id);

      // Backdrop (draft only; stripped at publish). mpp keeps 7 decimals: rounding
      // metres-per-pixel to 1 mm would be a 6 % scale error on a 4000 px plan.
      if (l.backdrop != null) {
        const bd = l.backdrop;
        const bp2 = `${lp}.backdrop`;
        if (typeof bd !== 'object') c.err(bp2, 'must be an object');
        else {
          const id = isStr(bd.id) && /^[0-9a-f]{32}$/.test(bd.id) ? bd.id : null;
          if (!id) c.err(`${bp2}.id`, 'must be an upload key');
          const mppRaw = isNum(bd.mpp) ? bd.mpp : 0;
          if (mppRaw < 0.0001 || mppRaw > 1) c.err(`${bp2}.mpp`, 'metres per pixel must be 0.0001–1');
          level.backdrop = {
            id: id ?? '',
            cx: num(c, `${bp2}.cx`, bd.cx, { min: -5000, max: 5000, def: 0 }),
            cz: num(c, `${bp2}.cz`, bd.cz, { min: -5000, max: 5000, def: 0 }),
            mpp: Math.round(Math.min(1, Math.max(0.0001, mppRaw)) * 1e7) / 1e7,
            rot: normRot(num(c, `${bp2}.rot`, bd.rot, { def: 0 })),
            opacity: num(c, `${bp2}.opacity`, bd.opacity, { min: 0.05, max: 1, def: 0.5 }),
            locked: bd.locked === true,
            // Round 18: the scale was set on purpose (calibrated, a drawing's unit, or found from a dimension).
            calibrated: bd.calibrated === true,
          };
        }
      }
      if (!level.outline) c.pub(`${lp}.outline`, 'level has no floor outline');

      // Walls
      const wallIds = new Map();
      const walls = Array.isArray(l.walls) ? l.walls : [];
      if (walls.length > LIMITS.wallsPerLevel) c.err(`${lp}.walls`, `too many walls (max ${LIMITS.wallsPerLevel})`);
      for (const [wi, w] of walls.slice(0, LIMITS.wallsPerLevel).entries()) {
        const wp = `${lp}.walls[${wi}]`;
        if (!w || typeof w !== 'object') {
          c.err(wp, 'must be an object');
          continue;
        }
        const a = point(c, `${wp}.a`, w.a);
        const bb = point(c, `${wp}.b`, w.b);
        const len = Math.hypot(bb[0] - a[0], bb[1] - a[1]);
        if (len < 0.05) c.err(wp, 'wall is shorter than 5 cm');
        const wall = {
          id: takeId(`${wp}.id`, w.id, 'w'),
          a,
          b: bb,
          t: num(c, `${wp}.t`, w.t, { min: 0.05, max: 2, def: 0.2 }),
          kind: oneOf(c, `${wp}.kind`, w.kind, WALL_KINDS, 'solid'),
        };
        wallIds.set(wall.id, len);
        level.walls.push(wall);
      }

      // Openings
      const openings = Array.isArray(l.openings) ? l.openings : [];
      if (openings.length > LIMITS.openingsPerLevel) c.err(`${lp}.openings`, `too many openings (max ${LIMITS.openingsPerLevel})`);
      for (const [oi, o] of openings.slice(0, LIMITS.openingsPerLevel).entries()) {
        const op = `${lp}.openings[${oi}]`;
        if (!o || typeof o !== 'object') {
          c.err(op, 'must be an object');
          continue;
        }
        const opening = {
          id: takeId(`${op}.id`, o.id, 'o'),
          wall: isStr(o.wall) ? o.wall : '',
          at: num(c, `${op}.at`, o.at, { min: 0, max: 1, def: 0.5 }),
          w: num(c, `${op}.w`, o.w, { min: 0.4, max: 30, def: 1.2 }),
          kind: oneOf(c, `${op}.kind`, o.kind, OPENING_KINDS, 'door'),
          label: text(c, `${op}.label`, o.label, { max: 80 }),
          props: plainProps(c, `${op}.props`, o.props),
        };
        if (!wallIds.has(opening.wall)) c.err(`${op}.wall`, 'must name a wall on the same level');
        else if (opening.w > wallIds.get(opening.wall) + 0.001) c.err(`${op}.w`, 'opening is wider than its wall');
        level.openings.push(opening);
      }

      // Spaces
      const spaces = Array.isArray(l.spaces) ? l.spaces : [];
      if (spaces.length > LIMITS.spacesPerLevel) c.err(`${lp}.spaces`, `too many spaces (max ${LIMITS.spacesPerLevel})`);
      for (const [si, s] of spaces.slice(0, LIMITS.spacesPerLevel).entries()) {
        const sp = `${lp}.spaces[${si}]`;
        if (!s || typeof s !== 'object') {
          c.err(sp, 'must be an object');
          continue;
        }
        const type = oneOf(c, `${sp}.type`, s.type, SPACE_TYPES, 'retail');
        const space = {
          id: takeId(`${sp}.id`, s.id, 'sp'),
          name: text(c, `${sp}.name`, s.name, { max: 80 }),
          type,
          customType: text(c, `${sp}.customType`, s.customType, { max: 60 }),
          shape: polygon(c, `${sp}.shape`, s.shape, { required: true, minArea: 0.1 }) ?? { outer: [], holes: [] },
          unitType: text(c, `${sp}.unitType`, s.unitType, { max: 100 }),
          floorLabel: text(c, `${sp}.floorLabel`, s.floorLabel, { max: 100 }),
          sloped: s.sloped === true,
          walkable: s.walkable !== false,
          meta: plainProps(c, `${sp}.meta`, s.meta),
        };
        if (type === 'custom' && !space.customType) c.err(`${sp}.customType`, 'custom spaces need a custom type name');
        if (!space.name && ['retail', 'food', 'anchor', 'service', 'office'].includes(type)) c.pub(`${sp}.name`, 'unit has no name');
        level.spaces.push(space);
      }

      // Features
      const features = Array.isArray(l.features) ? l.features : [];
      if (features.length > LIMITS.featuresPerLevel) c.err(`${lp}.features`, `too many features (max ${LIMITS.featuresPerLevel})`);
      for (const [fi, f] of features.slice(0, LIMITS.featuresPerLevel).entries()) {
        const fp = `${lp}.features[${fi}]`;
        if (!f || typeof f !== 'object') {
          c.err(fp, 'must be an object');
          continue;
        }
        const def = FEATURE_TYPES[f.type];
        if (!def) {
          c.err(`${fp}.type`, `unknown feature type "${f.type}"`);
          continue;
        }
        const feature = {
          id: takeId(`${fp}.id`, f.id, 'ft'),
          type: f.type,
          x: num(c, `${fp}.x`, f.x, {}),
          z: num(c, `${fp}.z`, f.z, {}),
          rot: normRot(num(c, `${fp}.rot`, f.rot, { def: 0 })),
          label: text(c, `${fp}.label`, f.label, { max: 80 }),
          props: plainProps(c, `${fp}.props`, f.props),
        };
        for (const dim of ['w', 'd', 'h']) {
          if (f[dim] == null) continue;
          const range = def.resize?.[dim];
          if (!range) {
            c.err(`${fp}.${dim}`, `${def.label} has a fixed ${dim}`);
            continue;
          }
          feature[dim] = num(c, `${fp}.${dim}`, f[dim], { min: range[0], max: range[1] });
        }
        level.features.push(feature);
      }

      out.levels.push(level);
    }
    buildings.push(out);
  }

  // ---- Connectors ----
  const connectors = [];
  const inConn = Array.isArray(input.connectors) ? input.connectors : [];
  if (inConn.length > LIMITS.connectors) c.err('connectors', `too many connectors (max ${LIMITS.connectors})`);
  for (const [ci, cn] of inConn.slice(0, LIMITS.connectors).entries()) {
    const cp = `connectors[${ci}]`;
    if (!cn || typeof cn !== 'object') {
      c.err(cp, 'must be an object');
      continue;
    }
    const kind = oneOf(c, `${cp}.kind`, cn.kind, CONNECTOR_KINDS, 'stairs');
    const conn = {
      id: takeId(`${cp}.id`, cn.id, 'cn'),
      kind,
      name: text(c, `${cp}.name`, cn.name, { max: 80 }),
      oneWay: cn.oneWay === true,
      walkable: cn.walkable !== false,
      endpoints: [],
    };
    if (conn.oneWay && !ONE_WAY_CAPABLE.includes(kind)) c.err(`${cp}.oneWay`, `${kind} cannot be one-way`);
    const eps = Array.isArray(cn.endpoints) ? cn.endpoints : [];
    if (eps.length < 2) c.err(`${cp}.endpoints`, 'needs at least two endpoints');
    if (eps.length > LIMITS.endpointsPerConnector) c.err(`${cp}.endpoints`, `too many endpoints (max ${LIMITS.endpointsPerConnector})`);
    if (['escalator', 'moving_walkway'].includes(kind) && eps.length !== 2) c.err(`${cp}.endpoints`, `${kind} must have exactly two endpoints`);
    for (const [ei, e] of eps.slice(0, LIMITS.endpointsPerConnector).entries()) {
      const ep = `${cp}.endpoints[${ei}]`;
      if (!e || typeof e !== 'object') {
        c.err(ep, 'must be an object');
        continue;
      }
      const endpoint = {
        level: isStr(e.level) ? e.level : '',
        x: num(c, `${ep}.x`, e.x, {}),
        z: num(c, `${ep}.z`, e.z, {}),
        rot: normRot(num(c, `${ep}.rot`, e.rot, { def: 0 })),
        w: num(c, `${ep}.w`, e.w, { min: 0.5, max: 30, def: 1.4 }),
        len: num(c, `${ep}.len`, e.len, { min: 0.5, max: 200, def: 4 }),
      };
      levelsOfConnectorNeed.push([`${ep}.level`, endpoint.level]);
      conn.endpoints.push(endpoint);
    }
    const distinct = new Set(conn.endpoints.map((e) => e.level));
    if (conn.endpoints.length >= 2 && distinct.size < 2 && kind !== 'walkway' && kind !== 'bridge') {
      c.err(`${cp}.endpoints`, 'endpoints must be on at least two different levels');
    }
    connectors.push(conn);
  }
  for (const [path, lvl] of levelsOfConnectorNeed) {
    if (!levelIds.has(lvl)) c.err(path, 'must name a level in this map');
  }

  // ---- Completeness (publish only) ----
  const hasEntrance = buildings.some((b) => b.levels.some((l) => l.features.some((f) => f.type === 'entrance') || l.openings.some((o) => o.kind === 'entrance')));
  if (!hasEntrance) c.pub('layout', 'the map has no entrance (add an entrance feature or an entrance opening)');

  const layout = { spec: 1, units: 'm', catalog, buildings, connectors };
  return { layout, problems: c.problems, publishProblems: c.publishProblems };
}

/** The layout without any draft-only backdrops: what gets published. */
export function publishable(layout) {
  const out = structuredClone(layout);
  for (const b of out.buildings ?? []) {
    for (const l of b.levels ?? []) delete l.backdrop;
  }
  return out;
}

/** Copies backdrops from `from` onto `to` for levels that still exist (used on rollback). */
export function reattachBackdrops(to, from) {
  const byLevel = new Map();
  for (const b of from?.buildings ?? []) for (const l of b.levels ?? []) if (l.backdrop) byLevel.set(l.id, l.backdrop);
  for (const b of to.buildings ?? []) for (const l of b.levels ?? []) if (byLevel.has(l.id)) l.backdrop = byLevel.get(l.id);
  return to;
}

/** Flat index of spaces for store linking: spaceKey → { building, level, name, type }. */
export function spaceIndex(layout) {
  const out = [];
  for (const b of layout?.buildings ?? []) {
    for (const l of b.levels ?? []) {
      for (const s of l.spaces ?? []) {
        out.push({ key: s.id, name: s.name, type: s.type, buildingId: b.id, buildingName: b.name, levelId: l.id, levelName: l.name });
      }
    }
  }
  return out;
}

export function countSpaces(layout) {
  return spaceIndex(layout).length;
}

/**
 * A starter document: one building with one rectangular level. With
 * `outline: false` (a map started from an uploaded plan, Round 17) the level
 * has no outline yet; it comes from the plan or the AI reading.
 */
export function blankLayout({ buildingName = 'Main building', levelName = 'Ground floor', width = 100, depth = 60, outline = true } = {}) {
  return {
    spec: 1,
    units: 'm',
    catalog: CATALOG_VERSION,
    buildings: [
      {
        id: 'bd-main00',
        name: buildingName,
        origin: [0, 0],
        rot: 0,
        levels: [
          {
            id: 'lv-ground',
            name: levelName,
            elevation: 0,
            height: 4,
            offset: [0, 0],
            rot: 0,
            outline: outline ? { outer: [[0, 0], [width, 0], [width, depth], [0, depth]], holes: [] } : null,
            walls: [],
            openings: [],
            spaces: [],
            features: [],
          },
        ],
      },
    ],
    connectors: [],
  };
}
