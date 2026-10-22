// Synthetic plans shared by the Round 18 tests.
import { PNG } from 'pngjs';

/**
 * A 2000 × 1400 px plan at 100 px per metre: a 16 × 10 m box (walls drawn as two
 * 3 px lines 15 cm apart), a partition at x = 10 m with a 1 m door, a desk
 * (two lines 60 cm apart: not a wall), a single-line glass wall at x = 14 m (not
 * measured: the AI reports it), and a dimension line above the box.
 */
export function drawnPlan() {
  const W = 2000;
  const H = 1400;
  const png = new PNG({ width: W, height: H });
  png.data.fill(255);
  const ink = (x, y) => {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const o = (y * W + x) * 4;
    png.data[o] = png.data[o + 1] = png.data[o + 2] = 20;
  };
  const hBand = (x0, x1, y) => {
    for (let x = x0; x <= x1; x++) for (const dy of [0, 1, 2, 15, 16, 17]) ink(x, y + dy);
  };
  const vBand = (y0, y1, x) => {
    for (let y = y0; y <= y1; y++) for (const dx of [0, 1, 2, 15, 16, 17]) ink(x + dx, y);
  };
  hBand(200, 1800, 200);
  hBand(200, 1800, 1200);
  vBand(200, 1217, 200);
  vBand(200, 1217, 1800);
  vBand(217, 600, 1000);
  vBand(700, 1200, 1000);
  // A 1.5 × 0.6 m desk: two lines 60 cm apart.
  for (let x = 400; x <= 550; x++) for (const y of [500, 501, 560, 561]) ink(x, y);
  // A single-line glass wall.
  for (let y = 217; y <= 1200; y++) ink(1400, y);
  // A dimension line above the box, with ticks.
  for (let x = 200; x <= 1800; x++) ink(x, 100);
  return PNG.sync.write(png);
}
