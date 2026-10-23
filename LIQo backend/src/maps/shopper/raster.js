// Raster helpers for the shopper package builder (Round 21, P1-08). A Grid
// covers one editor level in its own metres (x across, z down); cell (i, j)
// is column i, row j, its centre at (minX + (i + 0.5)·cell, minZ + (j + 0.5)·cell).
// Pure and deterministic: every loop runs in index order.

export class Grid {
  constructor(minX, minZ, maxX, maxZ, cell) {
    this.cell = cell;
    this.minX = minX;
    this.minZ = minZ;
    this.gw = Math.max(1, Math.ceil((maxX - minX) / cell));
    this.gh = Math.max(1, Math.ceil((maxZ - minZ) / cell));
    this.size = this.gw * this.gh;
  }

  cx(i) {
    return this.minX + (i + 0.5) * this.cell;
  }

  cz(j) {
    return this.minZ + (j + 0.5) * this.cell;
  }

  /** The cell index holding a point, or -1 outside the grid. */
  at(x, z) {
    const i = Math.floor((x - this.minX) / this.cell);
    const j = Math.floor((z - this.minZ) / this.cell);
    return i < 0 || j < 0 || i >= this.gw || j >= this.gh ? -1 : j * this.gw + i;
  }

  center(idx) {
    return [this.cx(idx % this.gw), this.cz(Math.floor(idx / this.gw))];
  }
}

/**
 * Fills the cells whose centres are inside a polygon (outer ring minus holes,
 * even-odd) with [value], calling set(idx). Scanline per row.
 */
export function fillPolygon(grid, rings, set) {
  let minZ = Infinity;
  let maxZ = -Infinity;
  for (const ring of rings) for (const [, z] of ring) {
    if (z < minZ) minZ = z;
    if (z > maxZ) maxZ = z;
  }
  const j0 = Math.max(0, Math.floor((minZ - grid.minZ) / grid.cell));
  const j1 = Math.min(grid.gh - 1, Math.ceil((maxZ - grid.minZ) / grid.cell));
  const xs = [];
  for (let j = j0; j <= j1; j++) {
    const z = grid.cz(j);
    xs.length = 0;
    for (const ring of rings) {
      for (let k = 0; k < ring.length; k++) {
        const [x1, z1] = ring[k];
        const [x2, z2] = ring[(k + 1) % ring.length];
        if (z1 <= z === z2 <= z) continue;
        xs.push(x1 + ((z - z1) / (z2 - z1)) * (x2 - x1));
      }
    }
    xs.sort((a, b) => a - b);
    for (let k = 0; k + 1 < xs.length; k += 2) {
      const i0 = Math.max(0, Math.ceil((xs[k] - grid.minX) / grid.cell - 0.5));
      const i1 = Math.min(grid.gw - 1, Math.floor((xs[k + 1] - grid.minX) / grid.cell - 0.5));
      for (let i = i0; i <= i1; i++) set(j * grid.gw + i);
    }
  }
}

/** The four corners of a rectangle centred on (x, z), [w] along angle [rot] (radians), [d] across. */
export function rectCorners(x, z, w, d, rot) {
  const c = Math.cos(rot);
  const s = Math.sin(rot);
  const hw = w / 2;
  const hd = d / 2;
  return [
    [x - hw * c + hd * s, z - hw * s - hd * c],
    [x + hw * c + hd * s, z + hw * s - hd * c],
    [x + hw * c - hd * s, z + hw * s + hd * c],
    [x - hw * c - hd * s, z - hw * s + hd * c],
  ];
}

/**
 * Every cell a segment of thickness [t] touches (conservative: any cell whose
 * square comes within t/2 of the segment, so diagonal walls never leak).
 */
export function fillSegment(grid, ax, az, bx, bz, t, set) {
  const half = Math.max(t, grid.cell) / 2;
  const reach = half + grid.cell * 0.7072; // half the cell's diagonal
  const i0 = Math.max(0, Math.floor((Math.min(ax, bx) - reach - grid.minX) / grid.cell));
  const i1 = Math.min(grid.gw - 1, Math.floor((Math.max(ax, bx) + reach - grid.minX) / grid.cell));
  const j0 = Math.max(0, Math.floor((Math.min(az, bz) - reach - grid.minZ) / grid.cell));
  const j1 = Math.min(grid.gh - 1, Math.floor((Math.max(az, bz) + reach - grid.minZ) / grid.cell));
  const dx = bx - ax;
  const dz = bz - az;
  const len2 = dx * dx + dz * dz || 1e-12;
  const lim2 = (half + grid.cell * 0.5) ** 2;
  for (let j = j0; j <= j1; j++) {
    const z = grid.cz(j);
    for (let i = i0; i <= i1; i++) {
      const x = grid.cx(i);
      const u = Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / len2));
      const px = ax + u * dx - x;
      const pz = az + u * dz - z;
      if (px * px + pz * pz <= lim2) set(j * grid.gw + i);
    }
  }
}

/** Squared Euclidean distance (in cells²) from every cell to the nearest cell where mask is 0 (Felzenszwalb–Huttenlocher). */
export function distanceTransform(grid, mask) {
  const { gw, gh } = grid;
  const INF = 1e12;
  const out = new Float64Array(gw * gh);
  const f = new Float64Array(Math.max(gw, gh));
  const d = new Float64Array(Math.max(gw, gh));
  const v = new Int32Array(Math.max(gw, gh));
  const zz = new Float64Array(Math.max(gw, gh) + 1);
  const pass = (n) => {
    let k = 0;
    v[0] = 0;
    zz[0] = -INF;
    zz[1] = INF;
    for (let q = 1; q < n; q++) {
      let s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      while (s <= zz[k]) {
        k -= 1;
        s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      }
      k += 1;
      v[k] = q;
      zz[k] = s;
      zz[k + 1] = INF;
    }
    k = 0;
    for (let q = 0; q < n; q++) {
      while (zz[k + 1] < q) k += 1;
      d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
    }
  };
  for (let i = 0; i < gw; i++) {
    for (let j = 0; j < gh; j++) f[j] = mask[j * gw + i] ? INF : 0;
    pass(gh);
    for (let j = 0; j < gh; j++) out[j * gw + i] = d[j];
  }
  for (let j = 0; j < gh; j++) {
    for (let i = 0; i < gw; i++) f[i] = out[j * gw + i];
    pass(gw);
    for (let i = 0; i < gw; i++) out[j * gw + i] = d[i];
  }
  // The grid's border counts as an obstacle: nothing walks off the edge.
  for (let i = 0; i < gw; i++) {
    for (const j of [0, gh - 1]) out[j * gw + i] = Math.min(out[j * gw + i], mask[j * gw + i] ? 1 : 0);
  }
  for (let j = 0; j < gh; j++) {
    for (const i of [0, gw - 1]) out[j * gw + i] = Math.min(out[j * gw + i], mask[j * gw + i] ? 1 : 0);
  }
  return out;
}

/** 4-connected regions of a mask: Int32Array of labels (−1 = not in the mask) and their cell counts. */
export function label4(grid, mask) {
  const { gw, size } = grid;
  const label = new Int32Array(size).fill(-1);
  const counts = [];
  const stack = new Int32Array(size);
  for (let s = 0; s < size; s++) {
    if (!mask[s] || label[s] >= 0) continue;
    const id = counts.length;
    let top = 0;
    stack[top++] = s;
    label[s] = id;
    let n = 0;
    while (top) {
      const c = stack[--top];
      n += 1;
      const i = c % gw;
      const nb = [i > 0 ? c - 1 : -1, i < gw - 1 ? c + 1 : -1, c - gw, c + gw];
      for (const x of nb) {
        if (x >= 0 && x < size && mask[x] && label[x] < 0) {
          label[x] = id;
          stack[top++] = x;
        }
      }
    }
    counts.push(n);
  }
  return { label, counts };
}

/** True when the straight line between two points stays on cells where ok(idx) holds (sampled every half cell). */
export function lineOk(grid, ax, az, bx, bz, ok) {
  const len = Math.hypot(bx - ax, bz - az);
  const steps = Math.max(1, Math.ceil(len / (grid.cell * 0.5)));
  for (let s = 0; s <= steps; s++) {
    const t = s / steps;
    const idx = grid.at(ax + (bx - ax) * t, az + (bz - az) * t);
    if (idx < 0 || !ok(idx)) return false;
  }
  return true;
}

/** Douglas–Peucker on an open polyline of [x, z] points. */
export function simplifyLine(pts, tol) {
  if (pts.length < 3) return pts.slice();
  const keep = new Uint8Array(pts.length);
  keep[0] = 1;
  keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let maxD = 0;
    let idx = -1;
    const [x0, z0] = pts[s];
    const [x1, z1] = pts[e];
    const dx = x1 - x0;
    const dz = z1 - z0;
    const len = Math.hypot(dx, dz);
    for (let i = s + 1; i < e; i++) {
      const dd = len < 1e-9 ? Math.hypot(pts[i][0] - x0, pts[i][1] - z0) : Math.abs(dz * pts[i][0] - dx * pts[i][1] + x1 * z0 - z1 * x0) / len;
      if (dd > maxD) {
        maxD = dd;
        idx = i;
      }
    }
    if (maxD > tol && idx > 0) {
      keep[idx] = 1;
      stack.push([s, idx], [idx, e]);
    }
  }
  return pts.filter((_, i) => keep[i]);
}

/** Signed area of a ring (positive when it runs clockwise on screen, i.e. counter-clockwise in x/z maths with z down). */
export function signedArea(ring) {
  let a = 0;
  for (let k = 0; k < ring.length; k++) {
    const [x1, z1] = ring[k];
    const [x2, z2] = ring[(k + 1) % ring.length];
    a += x1 * z2 - x2 * z1;
  }
  return a / 2;
}

export function pointInRing([x, z], ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, zi] = ring[i];
    const [xj, zj] = ring[j];
    if (zi > z !== zj > z && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

export function inPolygon(p, shape) {
  if (!shape?.outer || !pointInRing(p, shape.outer)) return false;
  for (const h of shape.holes ?? []) if (pointInRing(p, h)) return false;
  return true;
}
