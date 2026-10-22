// Draws a vector plan as the picture people see under the level (Round 16):
// white paper, dark lines, no text (texts go to the AI as data). The mapping from
// drawing units to picture pixels is kept so walls can be laid on the exact lines.

import { PNG } from 'pngjs';

const MAX_SIDE = 6000;
const MAX_PIXELS = 24_000_000;
const MIN_SIDE = 64;
const MARGIN = 20;
const PX_PER_M = 50;

/**
 * Picks the drawing → picture mapping: about 50 px per metre when the unit is
 * known, else 4000 px on the long side; always inside the size limits.
 */
export function layoutFor(vector) {
  const b = vector.bounds;
  const w = Math.max(b.maxX - b.minX, 1e-9);
  const h = Math.max(b.maxY - b.minY, 1e-9);
  const long = Math.max(w, h);
  let k = vector.unitToM ? PX_PER_M * vector.unitToM : 4000 / long;
  k = Math.min(k, (MAX_SIDE - 2 * MARGIN) / long);
  if ((w * k + 2 * MARGIN) * (h * k + 2 * MARGIN) > MAX_PIXELS) k = Math.sqrt(MAX_PIXELS / ((w + 2 * MARGIN / k) * (h + 2 * MARGIN / k))) * 0.98;
  const width = Math.max(MIN_SIDE, Math.ceil(w * k + 2 * MARGIN));
  const height = Math.max(MIN_SIDE, Math.ceil(h * k + 2 * MARGIN));
  return { k, ox: MARGIN - b.minX * k, oy: MARGIN - b.minY * k, width, height };
}

/** Drawing units → picture pixels. */
export const toPx = (L, x, y) => [x * L.k + L.ox, y * L.k + L.oy];

/** Grey PNG of the lines. */
export function renderVector(vector, L = layoutFor(vector)) {
  const { width, height } = L;
  const g = Buffer.alloc(width * height, 255);
  const thick = Math.max(width, height) > 4000 ? 2 : 1;
  const ink = 35;
  const dot = (x, y) => {
    for (let dy = 0; dy < thick; dy++) {
      for (let dx = 0; dx < thick; dx++) {
        const px = x + dx;
        const py = y + dy;
        if (px >= 0 && py >= 0 && px < width && py < height) g[py * width + px] = ink;
      }
    }
  };
  const s = vector.segments;
  for (let i = 0; i < s.length; i += 5) {
    const [x0, y0] = toPx(L, s[i], s[i + 1]);
    const [x1, y1] = toPx(L, s[i + 2], s[i + 3]);
    const steps = Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)));
    if (steps === 0) {
      dot(Math.round(x0), Math.round(y0));
      continue;
    }
    for (let t = 0; t <= steps; t++) dot(Math.round(x0 + ((x1 - x0) * t) / steps), Math.round(y0 + ((y1 - y0) * t) / steps));
  }
  return PNG.sync.write({ width, height, data: g }, { colorType: 0, inputColorType: 0, bitDepth: 8, inputHasAlpha: false });
}
