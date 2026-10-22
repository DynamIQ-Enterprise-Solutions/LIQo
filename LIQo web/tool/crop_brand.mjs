// Cuts every brand image out of "LIQO Brand Guidelines Presentation.png" (the
// reference since 2026-10-22, replacing the old brand board). Usage, from the
// LIQo folder:  node "LIQo web/tool/crop_brand.mjs"   (needs pngjs, which the
// backend already installs).
//
// Owner decisions 2026-10-22:
// - Light-mode wordmark: the sheet's primary logo, without its tagline.
// - Dark-mode wordmark: the hero banner's white logo, background removed.
// - App and tab icons: the dark tile in dark mode, the light tile in light mode.
// - IQ mark: the sheet's standalone "Icon usage (alternative)" IQ; in dark mode
//   its dark I and arrow are turned white, like the hero logo.
//
// Precision rules:
// - Edges are matted, not keyed: every edge pixel is unmixed from its local
//   background, so no halo of the sheet's background stays on any edge.
// - Holes (inside Q and O) become transparent; the sheet's colour never shows.
// - Tiles get an analytic anti-aliased rounded mask, inset past the soft shadow.
// - Both wordmarks are aligned on the letters' height, so the logo is the same
//   size in light and dark mode; every image gets the same transparent margin.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..', '..');
const require = createRequire(path.join(ROOT, 'LIQo backend', 'package.json'));
const { PNG } = require('pngjs');

const sheet = PNG.sync.read(fs.readFileSync(path.join(ROOT, 'LIQO Brand Guidelines Presentation.png')));
const MARGIN = 2; // transparent pixels around every cut-out

// ---------------------------------------------------------------- helpers ---
const blank = (w, h) => new PNG({ width: w, height: h });
const idx = (img, x, y) => (y * img.width + x) * 4;
const rgb = (img, x, y) => { const i = idx(img, x, y); return [img.data[i], img.data[i + 1], img.data[i + 2]]; };
const lum = ([r, g, b]) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
const sat = ([r, g, b]) => Math.max(r, g, b) - Math.min(r, g, b);
const dist = (a, b) => Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]);

function crop(img, x0, y0, w, h) {
  const out = blank(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const s = idx(img, x0 + x, y0 + y), d = idx(out, x, y);
    out.data[d] = img.data[s]; out.data[d + 1] = img.data[s + 1]; out.data[d + 2] = img.data[s + 2]; out.data[d + 3] = 255;
  }
  return out;
}

/**
 * Matting. Each pixel is background, foreground or edge (by [classify]).
 * Background becomes transparent. An edge pixel P is unmixed from the mean
 * background B and mean foreground F around it: alpha = (P-B)·(F-B)/|F-B|²,
 * and its colour becomes F, so no background colour is left in the edge.
 */
function matte(img, classify, radius = 3) {
  const { width: w, height: h } = img;
  const cls = new Int8Array(w * h); // -1 bg, 1 fg, 0 edge
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) cls[y * w + x] = classify(rgb(img, x, y), x, y);
  const out = blank(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const k = y * w + x, d = k * 4;
    const P = rgb(img, x, y);
    if (cls[k] === 1) { out.data.set([...P, 255], d); continue; }
    if (cls[k] === -1) { out.data.set([...P, 0], d); continue; }
    const B = [0, 0, 0], F = [0, 0, 0];
    let nb = 0, nf = 0;
    for (let r = 1; r <= radius + 3 && (nb === 0 || nf === 0); r++) {
      for (let yy = Math.max(0, y - r); yy <= Math.min(h - 1, y + r); yy++) for (let xx = Math.max(0, x - r); xx <= Math.min(w - 1, x + r); xx++) {
        const c = cls[yy * w + xx];
        if (c === 0) continue;
        const q = rgb(img, xx, yy);
        if (c === -1) { B[0] += q[0]; B[1] += q[1]; B[2] += q[2]; nb++; } else { F[0] += q[0]; F[1] += q[1]; F[2] += q[2]; nf++; }
      }
    }
    if (nf === 0) { out.data.set([...P, 0], d); continue; }
    for (let c = 0; c < 3; c++) F[c] /= nf;
    if (nb === 0) { out.data.set([...P, 255], d); continue; }
    for (let c = 0; c < 3; c++) B[c] /= nb;
    const fb = [F[0] - B[0], F[1] - B[1], F[2] - B[2]];
    const pb = [P[0] - B[0], P[1] - B[1], P[2] - B[2]];
    const den = fb[0] * fb[0] + fb[1] * fb[1] + fb[2] * fb[2];
    const a = den < 1 ? 1 : Math.max(0, Math.min(1, (pb[0] * fb[0] + pb[1] * fb[1] + pb[2] * fb[2]) / den));
    // Colour: what P would be at full coverage, kept close to the local foreground.
    const col = a > 0.05 ? [0, 1, 2].map((c) => Math.max(0, Math.min(255, Math.round(B[c] + (P[c] - B[c]) / a)))) : F.map(Math.round);
    const mix = [0, 1, 2].map((c) => Math.round(0.5 * col[c] + 0.5 * F[c]));
    out.data.set([...mix, Math.round(a * 255)], d);
  }
  return out;
}

/** Light-sheet background: the board colour, as background only where it is open space or a large hole (inside Q and O). */
function lightBackgroundMask(img, bg) {
  const { width: w, height: h } = img;
  const near = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) near[y * w + x] = dist(rgb(img, x, y), bg) <= 14 ? 1 : 0;
  const label = new Int32Array(w * h).fill(-1);
  const keep = new Uint8Array(w * h);
  let next = 0;
  for (let s = 0; s < w * h; s++) {
    if (!near[s] || label[s] >= 0) continue;
    const stack = [s], members = [];
    label[s] = next;
    let touchesEdge = false;
    while (stack.length) {
      const k = stack.pop();
      members.push(k);
      const x = k % w, y = (k - x) / w;
      if (x === 0 || y === 0 || x === w - 1 || y === h - 1) touchesEdge = true;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        const kk = yy * w + xx;
        if (near[kk] && label[kk] < 0) { label[kk] = next; stack.push(kk); }
      }
    }
    // Open space, or a hole big enough to be the inside of a letter.
    if (touchesEdge || members.length >= 120) for (const k of members) keep[k] = 1;
    next++;
  }
  return keep;
}

function matteOnLight(img) {
  const bg = rgb(img, 0, 0);
  const isBg = lightBackgroundMask(img, bg);
  // Solid: dark ink, or strongly coloured. Everything between is an edge and gets unmixed.
  return matte(img, (p, x, y) => (isBg[y * img.width + x] ? -1 : lum(p) < 120 || sat(p) >= 110 ? 1 : 0));
}

function matteOnDark(img) {
  // The hero sits on a dark photo: background is dim, the logo is bright.
  return matte(img, (p) => {
    const v = Math.max(...p);
    return v <= 95 ? -1 : v >= 165 ? 1 : 0;
  }, 4);
}

/** Bounding box of visible pixels. */
function bounds(img, minAlpha = 10) {
  let x0 = img.width, y0 = img.height, x1 = -1, y1 = -1;
  for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
    if (img.data[idx(img, x, y) + 3] >= minAlpha) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  }
  return { x0, y0, x1, y1, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

/** Copies [b] of [img] onto a transparent canvas of w×h at (dx, dy). */
function place(img, b, w, h, dx, dy) {
  const out = blank(w, h);
  for (let y = 0; y < b.h; y++) for (let x = 0; x < b.w; x++) {
    const s = idx(img, b.x0 + x, b.y0 + y), d = idx(out, dx + x, dy + y);
    for (let c = 0; c < 4; c++) out.data[d + c] = img.data[s + c];
  }
  return out;
}

const trimmed = (img) => { const b = bounds(img); return place(img, b, b.w + 2 * MARGIN, b.h + 2 * MARGIN, MARGIN, MARGIN); };

/** Top and bottom of the L's stem (the letters' height), in the image's rows. */
function capRows(img) {
  const b = bounds(img, 128);
  // The stem of the L: the first visible columns.
  let top = img.height, bottom = -1;
  for (let x = b.x0 + 2; x <= b.x0 + 6; x++) for (let y = 0; y < img.height; y++) {
    if (img.data[idx(img, x, y) + 3] >= 128) { top = Math.min(top, y); bottom = Math.max(bottom, y); }
  }
  return { top, bottom, h: bottom - top + 1 };
}

/** Bicubic (Catmull-Rom) resize, alpha-premultiplied so edges stay clean. */
function resize(img, w, h) {
  const out = blank(w, h);
  const cub = (t) => { t = Math.abs(t); return t <= 1 ? 1.5 * t ** 3 - 2.5 * t ** 2 + 1 : t < 2 ? -0.5 * t ** 3 + 2.5 * t ** 2 - 4 * t + 2 : 0; };
  const sxr = img.width / w, syr = img.height / h;
  const supX = Math.max(1, sxr), supY = Math.max(1, syr);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const cx = (x + 0.5) * sxr - 0.5, cy = (y + 0.5) * syr - 0.5;
    let acc = [0, 0, 0, 0], wsum = 0;
    const rx = Math.ceil(2 * supX), ry = Math.ceil(2 * supY);
    for (let yy = Math.floor(cy) - ry + 1; yy <= Math.floor(cy) + ry; yy++) for (let xx = Math.floor(cx) - rx + 1; xx <= Math.floor(cx) + rx; xx++) {
      const wgt = cub((xx - cx) / supX) * cub((yy - cy) / supY);
      if (wgt === 0) continue;
      const sx = Math.min(img.width - 1, Math.max(0, xx)), sy = Math.min(img.height - 1, Math.max(0, yy));
      const i = idx(img, sx, sy), a = img.data[i + 3] / 255;
      acc[0] += img.data[i] * a * wgt; acc[1] += img.data[i + 1] * a * wgt; acc[2] += img.data[i + 2] * a * wgt; acc[3] += a * wgt;
      wsum += wgt;
    }
    const a = Math.max(0, Math.min(1, acc[3] / wsum));
    const d = idx(out, x, y);
    for (let c = 0; c < 3; c++) out.data[d + c] = a > 0 ? Math.max(0, Math.min(255, Math.round(acc[c] / wsum / a))) : 0;
    out.data[d + 3] = Math.round(a * 255);
  }
  return out;
}

/** Fits [img] into a transparent square of [size], centred, proportions kept. */
function square(img, size, inset = 0) {
  const box = size - 2 * inset;
  const s = Math.min(box / img.width, box / img.height);
  const w = Math.round(img.width * s), h = Math.round(img.height * s);
  const r = resize(img, w, h);
  return place(r, { x0: 0, y0: 0, w, h }, size, size, Math.floor((size - w) / 2), Math.floor((size - h) / 2));
}

/** Composites onto a flat colour (maskable install icons need no transparency). */
function flatten(img, c) {
  const out = blank(img.width, img.height);
  for (let i = 0; i < img.data.length; i += 4) {
    const a = img.data[i + 3] / 255;
    for (let k = 0; k < 3; k++) out.data[i + k] = Math.round(img.data[i + k] * a + c[k] * (1 - a));
    out.data[i + 3] = 255;
  }
  return out;
}

const written = [];
function write(rel, img) {
  const f = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, PNG.sync.write(img));
  written.push(`${rel}  ${img.width}x${img.height}`);
}

// ------------------------------------------------------------- wordmarks ---
// Light: the primary logo's letters (rows 419-536; the tagline starts at 546).
const lightWord = trimmed(matteOnLight(crop(sheet, 70, 410, 360, 131)));
// Dark: the hero's white logo (columns 241-751; the divider at 800 is left out).
const darkWord = trimmed(matteOnDark(crop(sheet, 232, 86, 530, 210)));

// Same letter height in both modes, each at its own full resolution: both
// canvases get the same space above and below the letters, measured in
// letter heights, so at any display height the letters come out the same size.
const capL = capRows(lightWord), capD = capRows(darkWord);
const aboveR = Math.max(capL.top / capL.h, capD.top / capD.h);
const belowR = Math.max((lightWord.height - 1 - capL.bottom) / capL.h, (darkWord.height - 1 - capD.bottom) / capD.h);
const align = (img, cap) => {
  const top = Math.round(cap.h * aboveR);
  const h = top + cap.h + Math.round(cap.h * belowR);
  return place(img, { x0: 0, y0: 0, w: img.width, h: img.height }, img.width, h, 0, top - cap.top);
};
const logoLight = align(lightWord, capL);
const logoDark = align(darkWord, capD);
write('LIQo web/assets/brand/logo-light.png', logoLight);
write('LIQo web/assets/brand/logo-dark.png', logoDark);

// ----------------------------------------------------------------- tiles ---
// Edges measured on the sheet:
// - dark tile: 50% crossing of its edge, columns 502-648, rows 426-563;
// - light tile: between its soft shadow lines (columns 673/818, rows 426/565),
//   so columns 675-816, rows 428-563.
const darkBox = { x0: 502, y0: 426, w: 147, h: 138 };
const lightBox = { x0: 675, y0: 428, w: 142, h: 136 };

// Corner radius from the dark tile's corner: along the diagonal the edge is
// met after k = r(1 - 1/sqrt 2) pixels.
let k = 0;
while (k < 40 && lum(rgb(sheet, darkBox.x0 + k, darkBox.y0 + k)) > 130) k++;
const radiusShare = k / (1 - Math.SQRT1_2) / darkBox.w;

/**
 * The tile, inset past its soft edge and the sheet's bevel, scaled to [w]×[h]
 * (both tiles come out the same size), with an analytic anti-aliased rounded mask.
 */
function tile(b, inset, w, h) {
  let t = crop(sheet, b.x0 + inset, b.y0 + inset, b.w - 2 * inset, b.h - 2 * inset);
  if (t.width !== w || t.height !== h) t = resize(t, w, h);
  const r = radiusShare * w;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    // Distance outside the rounded rectangle, sampled at the pixel centre.
    const px = x + 0.5, py = y + 0.5;
    const qx = Math.max(r - px, px - (w - r), 0), qy = Math.max(r - py, py - (h - r), 0);
    const d = Math.hypot(qx, qy) - r;
    const a = d <= -0.5 ? 1 : d >= 0.5 ? 0 : 0.5 - d;
    t.data[idx(t, x, y) + 3] = Math.round(255 * a);
  }
  return t;
}
const TILE_W = darkBox.w - 4, TILE_H = darkBox.h - 4;
const radius = Math.round(radiusShare * TILE_W);
const iconDark = tile(darkBox, 2, TILE_W, TILE_H);
const iconLight = tile(lightBox, 1, TILE_W, TILE_H);
write('LIQo web/assets/brand/icon-dark.png', iconDark);
write('LIQo web/assets/brand/icon-light.png', iconLight);

// Browser tab and install icons: square canvases, the tile centred, proportions kept.
write('LIQo web/web/favicon-dark.png', square(iconDark, 64));
write('LIQo web/web/favicon-light.png', square(iconLight, 64));
write('LIQo web/web/favicon.png', square(iconDark, 64));
for (const s of [192, 512]) {
  write(`LIQo web/web/icons/Icon-${s}.png`, square(iconDark, s));
  // Maskable: full-bleed brand dark, the tile inside the 80% safe zone.
  write(`LIQo web/web/icons/Icon-maskable-${s}.png`, flatten(square(iconDark, s, Math.round(s * 0.1)), [26, 26, 31]));
}

// ---------------------------------------------------------------- IQ mark ---
// "Icon usage (alternative)": measured at 1281-1448 × 433-570 on the light sheet.
const iqLight = trimmed(matteOnLight(crop(sheet, 1268, 422, 194, 160)));
// Dark mode: the dark I and the dark arrow become the hero logo's white; the
// orange Q stays. Neutral (unsaturated) dark pixels are the ones recoloured.
const white = (() => {
  const b = bounds(darkWord, 250);
  const samples = [];
  for (let y = b.y0; y <= b.y1; y++) for (let x = b.x0; x < b.x0 + 12; x++) { const i = idx(darkWord, x, y); if (darkWord.data[i + 3] === 255) samples.push([darkWord.data[i], darkWord.data[i + 1], darkWord.data[i + 2]]); }
  return [0, 1, 2].map((c) => Math.round(samples.reduce((s, p) => s + p[c], 0) / samples.length));
})();
// The I ends where the first empty column after it begins.
let gap = 0;
{
  const colHas = (x) => { for (let y = 0; y < iqLight.height; y++) if (iqLight.data[idx(iqLight, x, y) + 3] > 0) return true; return false; };
  let x = 0;
  while (x < iqLight.width && !colHas(x)) x++;
  while (x < iqLight.width && colHas(x)) x++;
  gap = x;
}
const iqDark = blank(iqLight.width, iqLight.height);
for (let y = 0; y < iqLight.height; y++) for (let x = 0; x < iqLight.width; x++) {
  const i = idx(iqLight, x, y);
  const p = [iqLight.data[i], iqLight.data[i + 1], iqLight.data[i + 2]], a = iqLight.data[i + 3];
  const arrow = x >= gap && sat(p) < 60 && lum(p) < 150;
  iqDark.data.set(x < gap || arrow ? [...white, a] : [...p, a], i);
}
write('LIQo web/assets/brand/iq-light.png', iqLight);
write('LIQo web/assets/brand/iq-dark.png', iqDark);

console.log(written.join('\n'));
console.log(`tile ${TILE_W}x${TILE_H}, radius ${radius}px; letter height ${capL.h}px light, ${capD.h}px dark; white ${white}`);
