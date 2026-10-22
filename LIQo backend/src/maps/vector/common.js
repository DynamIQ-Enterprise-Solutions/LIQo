// Shared pieces for vector plans (Round 16): DXF, DWG (via DXF) and SVG are all
// read into one shape, in drawing units with y pointing DOWN (like a picture):
//   { kind, units, unitToM, layers: [name], segments: Float64Array-like [x1,y1,x2,y2,layer]*,
//     texts: [{x, y, text, layer}], bounds: {minX, minY, maxX, maxY} }

export const UNIT_TO_M = Object.freeze({ mm: 0.001, cm: 0.01, m: 1, in: 0.0254, ft: 0.3048 });
export const UNIT_NAMES = Object.freeze({ mm: 'millimetres', cm: 'centimetres', m: 'metres', in: 'inches', ft: 'feet' });

/** Hard limits so a huge or hostile drawing cannot exhaust the server. */
export const MAX_SEGMENTS = 400_000;
export const MAX_TEXTS = 20_000;
export const MAX_LAYERS = 2_000;
export const MAX_DEPTH = 12; // nested blocks / groups

export class TooComplex extends Error {}

/** Collects segments, texts and layers while a drawing is walked. */
export class Collector {
  constructor() {
    this.seg = [];
    this.texts = [];
    this.layers = [];
    this.layerIndex = new Map();
    this.minX = Infinity;
    this.minY = Infinity;
    this.maxX = -Infinity;
    this.maxY = -Infinity;
  }

  layer(name) {
    const key = String(name ?? '0').slice(0, 120) || '0';
    let i = this.layerIndex.get(key);
    if (i == null) {
      if (this.layers.length >= MAX_LAYERS) return 0;
      i = this.layers.length;
      this.layers.push(key);
      this.layerIndex.set(key, i);
    }
    return i;
  }

  #grow(x, y) {
    if (x < this.minX) this.minX = x;
    if (y < this.minY) this.minY = y;
    if (x > this.maxX) this.maxX = x;
    if (y > this.maxY) this.maxY = y;
  }

  line(x1, y1, x2, y2, layer) {
    if (![x1, y1, x2, y2].every(Number.isFinite)) return;
    if (x1 === x2 && y1 === y2) return;
    if (this.seg.length / 5 >= MAX_SEGMENTS) throw new TooComplex('too many lines');
    this.seg.push(x1, y1, x2, y2, layer);
    this.#grow(x1, y1);
    this.#grow(x2, y2);
  }

  polyline(points, layer, closed = false) {
    for (let i = 1; i < points.length; i++) this.line(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1], layer);
    if (closed && points.length > 2) {
      const a = points[points.length - 1];
      this.line(a[0], a[1], points[0][0], points[0][1], layer);
    }
  }

  text(x, y, text, layer) {
    const t = String(text ?? '').replace(/\s+/g, ' ').trim();
    if (!t || !Number.isFinite(x) || !Number.isFinite(y)) return;
    if (this.texts.length >= MAX_TEXTS) return;
    this.texts.push({ x, y, text: t.slice(0, 120), layer });
    this.#grow(x, y);
  }

  result(kind, units) {
    const count = this.seg.length / 5;
    const layerCounts = new Array(this.layers.length).fill(0);
    for (let i = 0; i < count; i++) layerCounts[this.seg[i * 5 + 4]] += 1;
    return {
      kind,
      units: units ?? null,
      unitToM: units ? UNIT_TO_M[units] : null,
      layers: this.layers.map((name, i) => ({ name, lines: layerCounts[i] })),
      segments: this.seg,
      texts: this.texts,
      bounds: count || this.texts.length ? { minX: this.minX, minY: this.minY, maxX: this.maxX, maxY: this.maxY } : null,
    };
  }
}

// ---- 2D affine matrices [a, b, c, d, e, f]: x' = a x + c y + e, y' = b x + d y + f ----

export const IDENTITY = [1, 0, 0, 1, 0, 0];

export function multiply(m, n) {
  return [
    m[0] * n[0] + m[2] * n[1],
    m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3],
    m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4],
    m[1] * n[4] + m[3] * n[5] + m[5],
  ];
}

export function apply(m, x, y) {
  return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
}

export const translate = (x, y) => [1, 0, 0, 1, x, y];
export const scale = (sx, sy = sx) => [sx, 0, 0, sy, 0, 0];
export const rotate = (rad) => [Math.cos(rad), Math.sin(rad), -Math.sin(rad), Math.cos(rad), 0, 0];

/** Points along a circular arc (angles in radians, counter-clockwise from a0 to a1). */
export function arcPoints(cx, cy, r, a0, a1) {
  let sweep = a1 - a0;
  while (sweep <= 0) sweep += Math.PI * 2;
  const n = Math.max(4, Math.min(96, Math.ceil(sweep / (Math.PI / 24))));
  const out = [];
  for (let i = 0; i <= n; i++) {
    const a = a0 + (sweep * i) / n;
    out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return out;
}

/** Points along a cubic Bézier. */
export function cubicPoints(p0, p1, p2, p3, n = 12) {
  const out = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const u = 1 - t;
    out.push([
      u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
      u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
    ]);
  }
  return out;
}
