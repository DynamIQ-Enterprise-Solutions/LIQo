// Where shoppers can walk on one editor level (Round 21, P1-08), in that
// level's own metres. Walkable: the free area inside the level outline, plus
// spaces of a walkable type (corridor, atrium, outdoor, parking; the editor's
// walkable flag can only switch one off), minus every other space, every wall
// (with its thickness) and every blocking catalog feature. Openings are not
// cut into walls here; doors are joined explicitly (doors.js).
import { FEATURE_TYPES } from '../catalog.js';
import { Grid, fillPolygon, fillSegment, rectCorners, distanceTransform, label4 } from './raster.js';

export const WALKABLE_TYPES = new Set(['corridor', 'atrium', 'outdoor', 'parking']);
export const OUTDOOR_TYPES = new Set(['outdoor', 'parking']);

/** Shoppers keep this far from walls and shop fronts on the walkway network (closes small gaps in traced walls). */
export const CLEAR = 0.3;
const MIN_REGION_M2 = 2;
const MAX_CELLS = 6_000_000;

export const isWalkableSpace = (s) => WALKABLE_TYPES.has(s.type) && s.walkable !== false;

const rad = (deg) => ((Number(deg) || 0) * Math.PI) / 180;

function ringArea(ring) {
  let a = 0;
  for (let k = 0; k < ring.length; k++) {
    const [x1, z1] = ring[k];
    const [x2, z2] = ring[(k + 1) % ring.length];
    a += x1 * z2 - x2 * z1;
  }
  return Math.abs(a) / 2;
}

/** A blocking feature's footprint, or null. */
export function featureFootprint(f) {
  const def = FEATURE_TYPES[f.type];
  if (!def) return null;
  const w = f.w ?? def.size[0];
  const d = f.d ?? def.size[1];
  return rectCorners(f.x, f.z, w, d, rad(f.rot));
}

/**
 * The walkable area of [level]. [extraPoints] are other points that must be on
 * the grid (connector endpoints). [cellCap] lowers the cell limit in tests.
 */
export function levelArea(level, { extraPoints = [], cellCap = MAX_CELLS } = {}) {
  const pts = [];
  if (level.outline) pts.push(...level.outline.outer);
  for (const s of level.spaces ?? []) pts.push(...s.shape.outer);
  for (const w of level.walls ?? []) pts.push(w.a, w.b);
  for (const f of level.features ?? []) pts.push([f.x, f.z]);
  pts.push(...extraPoints);
  if (!pts.length) pts.push([0, 0]);
  let minX = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxZ = -Infinity;
  for (const [x, z] of pts) {
    minX = Math.min(minX, x);
    minZ = Math.min(minZ, z);
    maxX = Math.max(maxX, x);
    maxZ = Math.max(maxZ, z);
  }
  const margin = 2;
  minX -= margin;
  minZ -= margin;
  maxX += margin;
  maxZ += margin;
  const areaM2 = (maxX - minX) * (maxZ - minZ);
  let cell = Math.min(0.3, Math.max(0.15, Math.sqrt(areaM2 / 1.5e6)));
  while (areaM2 / (cell * cell) > cellCap) cell *= 1.25;
  const grid = new Grid(minX, minZ, maxX, maxZ, cell);
  const n = grid.size;

  const inOutline = new Uint8Array(n);
  if (level.outline) fillPolygon(grid, [level.outline.outer, ...(level.outline.holes ?? [])], (i) => (inOutline[i] = 1));

  // The space owning each cell: the smallest wins where spaces overlap.
  const spaces = [...(level.spaces ?? [])].map((s, k) => ({ s, k, a: ringArea(s.shape.outer) }));
  spaces.sort((x, y) => y.a - x.a || (x.s.id < y.s.id ? -1 : 1));
  const spaceId = new Int32Array(n).fill(-1);
  for (const { s, k } of spaces) fillPolygon(grid, [s.shape.outer, ...(s.shape.holes ?? [])], (i) => (spaceId[i] = k));

  const walk = new Uint8Array(n);
  const out = new Uint8Array(n);
  const list = level.spaces ?? [];
  for (let i = 0; i < n; i++) {
    const k = spaceId[i];
    if (k < 0) walk[i] = inOutline[i];
    else {
      walk[i] = isWalkableSpace(list[k]) ? 1 : 0;
      out[i] = OUTDOOR_TYPES.has(list[k].type) ? 1 : 0;
    }
  }

  // Walls (with their thickness) and blocking features stop people.
  const wallId = new Int32Array(n).fill(-1);
  (level.walls ?? []).forEach((w, k) => fillSegment(grid, w.a[0], w.a[1], w.b[0], w.b[1], w.t ?? 0.2, (i) => (wallId[i] = k)));
  const featureBlock = new Uint8Array(n);
  for (const f of level.features ?? []) {
    if (!FEATURE_TYPES[f.type]?.blocks) continue;
    const fp = featureFootprint(f);
    if (fp) fillPolygon(grid, [fp], (i) => (featureBlock[i] = 1));
  }
  for (let i = 0; i < n; i++) if (wallId[i] >= 0 || featureBlock[i]) walk[i] = 0;

  const d2 = distanceTransform(grid, walk);
  const clear2 = (CLEAR / cell) ** 2;
  const passable = new Uint8Array(n);
  for (let i = 0; i < n; i++) passable[i] = walk[i] && d2[i] >= clear2 ? 1 : 0;
  const { label, counts } = label4(grid, passable);
  const minCells = MIN_REGION_M2 / (cell * cell);
  for (let i = 0; i < n; i++) {
    if (label[i] >= 0 && counts[label[i]] < minCells) {
      passable[i] = 0;
      label[i] = -1;
    }
  }
  let passableM2 = 0;
  for (let i = 0; i < n; i++) passableM2 += passable[i];
  passableM2 *= cell * cell;

  return { grid, level, spaces: list, inOutline, spaceId, walk, out, wallId, featureBlock, d2, passable, region: label, passableM2 };
}
