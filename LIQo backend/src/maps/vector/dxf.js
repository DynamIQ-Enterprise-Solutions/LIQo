// DXF floor plans (Round 16). Model space only; blocks are expanded with their
// placement; curves become short straight pieces. The y axis is flipped so the
// result reads like a picture (y down).

import DxfParser from 'dxf-parser';
import { Collector, TooComplex, IDENTITY, MAX_DEPTH, apply, multiply, translate, scale, rotate, arcPoints } from './common.js';

// $INSUNITS codes we can turn into metres. 0 (unitless) and odd units ask the admin.
const INSUNITS = { 1: 'in', 2: 'ft', 4: 'mm', 5: 'cm', 6: 'm' };

export class DxfError extends Error {}

/** True when the bytes look like an ASCII DXF (optionally after comments). */
export function looksLikeDxf(buf) {
  const head = buf.subarray(0, 512).toString('latin1').replace(/^﻿/, '');
  return /^\s*(?:999\r?\n[^\n]*\r?\n\s*)*0\r?\n\s*SECTION\b/.test(head);
}

/** Binary DXF files are not read; people re-save them as ASCII DXF. */
export function looksLikeBinaryDxf(buf) {
  return buf.subarray(0, 22).toString('latin1') === 'AutoCAD Binary DXF\r\n\u001a\u0000';
}

/** MTEXT formatting codes out, plain words in. */
export function plainMText(s) {
  return String(s ?? '')
    .replace(/\\P/g, ' ')
    .replace(/\\[ACFHQTWfhqtwacp][^;\\{}]*;/g, '')
    .replace(/\\[LlOoKk]/g, '')
    .replace(/\\S([^;]*);/g, (_, x) => x.replace(/[#^]/g, '/'))
    .replace(/\\~/g, ' ')
    .replace(/\\\\/g, '\\')
    .replace(/[{}]/g, '')
    .replace(/%%[cdp]/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Points of a polyline, with bulges (arc pieces) expanded. */
function polyPoints(vertices, closed) {
  const out = [];
  const n = vertices.length;
  const last = closed ? n : n - 1;
  for (let i = 0; i < n; i++) {
    const v = vertices[i];
    out.push([v.x, v.y]);
    if (i >= last) continue;
    const b = Number(v.bulge) || 0;
    if (b === 0) continue;
    const w = vertices[(i + 1) % n];
    const chord = Math.hypot(w.x - v.x, w.y - v.y);
    if (chord === 0) continue;
    const theta = 4 * Math.atan(b);
    const r = chord / (2 * Math.sin(Math.abs(theta) / 2));
    const mx = (v.x + w.x) / 2;
    const my = (v.y + w.y) / 2;
    const h = Math.sqrt(Math.max(0, r * r - (chord / 2) ** 2)) * Math.sign(b) * (Math.abs(theta) > Math.PI ? -1 : 1);
    const cx = mx - (h * (w.y - v.y)) / chord;
    const cy = my + (h * (w.x - v.x)) / chord;
    const a0 = Math.atan2(v.y - cy, v.x - cx);
    const a1 = Math.atan2(w.y - cy, w.x - cx);
    const pts = b > 0 ? arcPoints(cx, cy, r, a0, a1) : arcPoints(cx, cy, r, a1, a0).reverse();
    for (const p of pts.slice(1, -1)) out.push(p);
  }
  return out;
}

/**
 * Reads a DXF file (Buffer). Returns the shared vector shape; units is null when
 * the file does not say a unit we can convert.
 */
export function readDxf(buffer) {
  if (looksLikeBinaryDxf(buffer)) throw new DxfError('Binary DXF files are not supported. Save the drawing as an ASCII DXF and upload again.');
  let doc;
  try {
    doc = new DxfParser().parseSync(buffer.toString('utf8'));
  } catch (err) {
    throw new DxfError(`The DXF file could not be read (${String(err?.message ?? err).slice(0, 120)}).`);
  }
  if (!doc || !Array.isArray(doc.entities)) throw new DxfError('The DXF file has no drawing in it.');
  const units = INSUNITS[Number(doc.header?.$INSUNITS)] ?? null;
  const blocks = doc.blocks ?? {};
  const c = new Collector();
  // DXF y points up; flip it so the drawing reads like a picture.
  const flip = scale(1, -1);

  const walk = (entities, m, depth, inheritedLayer) => {
    if (depth > MAX_DEPTH) return;
    for (const e of entities) {
      if (!e || e.inPaperSpace) continue;
      // Entities on layer "0" inside a block take the layer of the insert.
      const layerName = e.layer === '0' && inheritedLayer ? inheritedLayer : e.layer;
      const layer = c.layer(layerName);
      const P = (x, y) => apply(m, x, y);
      switch (e.type) {
        case 'LINE': {
          const [a, b] = e.vertices ?? [];
          if (a && b) {
            const p = P(a.x, a.y);
            const q = P(b.x, b.y);
            c.line(p[0], p[1], q[0], q[1], layer);
          }
          break;
        }
        case 'LWPOLYLINE':
        case 'POLYLINE': {
          const vs = (e.vertices ?? []).filter((v) => Number.isFinite(v?.x) && Number.isFinite(v?.y));
          if (vs.length < 2) break;
          const closed = e.shape === true || e.closed === true;
          c.polyline(polyPoints(vs, closed).map(([x, y]) => P(x, y)), layer, closed);
          break;
        }
        case 'ARC':
          if (e.center && e.radius > 0) c.polyline(arcPoints(e.center.x, e.center.y, e.radius, e.startAngle, e.endAngle).map(([x, y]) => P(x, y)), layer);
          break;
        case 'CIRCLE':
          if (e.center && e.radius > 0) c.polyline(arcPoints(e.center.x, e.center.y, e.radius, 0, Math.PI * 2).map(([x, y]) => P(x, y)), layer);
          break;
        case 'ELLIPSE': {
          if (!e.center || !e.majorAxisEndPoint) break;
          const ax = e.majorAxisEndPoint.x;
          const ay = e.majorAxisEndPoint.y;
          const ra = Math.hypot(ax, ay);
          const rb = ra * (Number(e.axisRatio) || 1);
          const rot = Math.atan2(ay, ax);
          let s = Number(e.startAngle) || 0;
          let t = Number.isFinite(e.endAngle) ? e.endAngle : Math.PI * 2;
          if (t <= s) t += Math.PI * 2;
          const pts = [];
          for (let i = 0; i <= 48; i++) {
            const u = s + ((t - s) * i) / 48;
            const x = ra * Math.cos(u);
            const y = rb * Math.sin(u);
            pts.push(P(e.center.x + x * Math.cos(rot) - y * Math.sin(rot), e.center.y + x * Math.sin(rot) + y * Math.cos(rot)));
          }
          c.polyline(pts, layer);
          break;
        }
        case 'SPLINE': {
          // The control or fit points give a close enough line for a plan.
          const pts = (e.fitPoints?.length ? e.fitPoints : e.controlPoints ?? []).filter((v) => Number.isFinite(v?.x));
          if (pts.length >= 2) c.polyline(pts.map((v) => P(v.x, v.y)), layer, e.closed === true);
          break;
        }
        case 'SOLID':
        case '3DFACE': {
          const pts = (e.points ?? e.vertices ?? []).filter((v) => Number.isFinite(v?.x));
          if (pts.length >= 3) c.polyline(pts.map((v) => P(v.x, v.y)), layer, true);
          break;
        }
        case 'TEXT': {
          const at = e.startPoint ?? e.position;
          if (at) {
            const p = P(at.x, at.y);
            c.text(p[0], p[1], plainMText(e.text), layer);
          }
          break;
        }
        case 'MTEXT': {
          const at = e.position;
          if (at) {
            const p = P(at.x, at.y);
            c.text(p[0], p[1], plainMText(e.text), layer);
          }
          break;
        }
        case 'INSERT': {
          const block = blocks[e.name];
          if (!block?.entities?.length || !e.position) break;
          const base = block.position ?? { x: 0, y: 0 };
          const cols = Math.max(1, Math.min(50, e.columnCount ?? 1));
          const rows = Math.max(1, Math.min(50, e.rowCount ?? 1));
          for (let r = 0; r < rows; r++) {
            for (let k = 0; k < cols; k++) {
              const local = multiply(
                translate(e.position.x, e.position.y),
                multiply(
                  rotate(((Number(e.rotation) || 0) * Math.PI) / 180),
                  multiply(translate(k * (e.columnSpacing ?? 0), r * (e.rowSpacing ?? 0)), multiply(scale(e.xScale ?? 1, e.yScale ?? 1), translate(-base.x, -base.y))),
                ),
              );
              walk(block.entities, multiply(m, local), depth + 1, layerName);
            }
          }
          break;
        }
        default:
          break;
      }
    }
  };

  try {
    walk(doc.entities, multiply(flip, IDENTITY), 0, null);
  } catch (err) {
    if (err instanceof TooComplex) throw new DxfError('This drawing is too complex to read (more than 400 000 lines). Remove furniture or detail layers and try again.');
    throw err;
  }
  const out = c.result('dxf', units);
  if (!out.bounds || out.segments.length === 0) throw new DxfError('No lines were found in the DXF model space.');
  return out;
}
