// SVG floor plans (Round 16). Read as data only: the XML parser keeps entities
// unexpanded, scripts, styles, images and foreign content are skipped, and the
// SVG itself is never served back to a browser (people see our own PNG).
// SVG has no real-world unit, so the scale comes from the two-click calibration.

import { XMLParser } from 'fast-xml-parser';
import { SVGPathData } from 'svg-pathdata';
import { Collector, TooComplex, IDENTITY, MAX_DEPTH, apply, multiply, translate, scale, rotate, arcPoints, cubicPoints } from './common.js';

export class SvgError extends Error {}

/** True when the bytes are an SVG document (after an optional prolog and comments). */
export function looksLikeSvg(buf) {
  const head = buf.subarray(0, 4096).toString('utf8').replace(/^﻿/, '').trimStart();
  if (!head.startsWith('<')) return false;
  return /<svg[\s>]/i.test(head);
}

const SKIP = new Set(['script', 'style', 'defs', 'symbol', 'clipPath', 'mask', 'pattern', 'marker', 'image', 'foreignObject', 'metadata', 'title', 'desc', 'linearGradient', 'radialGradient', 'filter']);

const num = (v, d = 0) => {
  const n = Number.parseFloat(v);
  return Number.isFinite(n) ? n : d;
};

/** The transform attribute as a matrix. */
export function parseTransform(s) {
  let m = IDENTITY;
  if (!s) return m;
  const re = /(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/g;
  let hit;
  while ((hit = re.exec(String(s)))) {
    const a = hit[2].split(/[\s,]+/).filter(Boolean).map(Number);
    let t = IDENTITY;
    switch (hit[1]) {
      case 'matrix':
        if (a.length === 6) t = a;
        break;
      case 'translate':
        t = translate(a[0] || 0, a[1] || 0);
        break;
      case 'scale':
        t = scale(a[0] ?? 1, a[1] ?? a[0] ?? 1);
        break;
      case 'rotate': {
        const r = rotate(((a[0] || 0) * Math.PI) / 180);
        t = a.length >= 3 ? multiply(translate(a[1], a[2]), multiply(r, translate(-a[1], -a[2]))) : r;
        break;
      }
      case 'skewX':
        t = [1, 0, Math.tan(((a[0] || 0) * Math.PI) / 180), 1, 0, 0];
        break;
      case 'skewY':
        t = [1, Math.tan(((a[0] || 0) * Math.PI) / 180), 0, 1, 0, 0];
        break;
    }
    m = multiply(m, t);
  }
  return m;
}

function pointsAttr(s) {
  const n = String(s ?? '').split(/[\s,]+/).filter(Boolean).map(Number);
  const out = [];
  for (let i = 0; i + 1 < n.length; i += 2) if (Number.isFinite(n[i]) && Number.isFinite(n[i + 1])) out.push([n[i], n[i + 1]]);
  return out;
}

function textOf(children) {
  let s = '';
  for (const ch of children ?? []) {
    if (ch['#text'] != null) s += ` ${ch['#text']}`;
    for (const k of Object.keys(ch)) if (k !== '#text' && k !== ':@' && Array.isArray(ch[k])) s += textOf(ch[k]);
  }
  return s;
}

/** Path data as polylines (each sub-path one list of points). */
function pathPolylines(d) {
  let data;
  try {
    data = new SVGPathData(String(d ?? '')).toAbs().normalizeHVZ(false).normalizeST().qtToC().aToC();
  } catch {
    return [];
  }
  const lines = [];
  let cur = null;
  let x = 0;
  let y = 0;
  let sx = 0;
  let sy = 0;
  for (const c of data.commands) {
    switch (c.type) {
      case SVGPathData.MOVE_TO:
        cur = [[c.x, c.y]];
        lines.push(cur);
        x = sx = c.x;
        y = sy = c.y;
        break;
      case SVGPathData.LINE_TO:
        if (!cur) lines.push((cur = [[x, y]]));
        cur.push([c.x, c.y]);
        x = c.x;
        y = c.y;
        break;
      case SVGPathData.CURVE_TO:
        if (!cur) lines.push((cur = [[x, y]]));
        for (const p of cubicPoints([x, y], [c.x1, c.y1], [c.x2, c.y2], [c.x, c.y]).slice(1)) cur.push(p);
        x = c.x;
        y = c.y;
        break;
      case SVGPathData.CLOSE_PATH:
        if (cur) cur.push([sx, sy]);
        x = sx;
        y = sy;
        cur = null;
        break;
      default:
        break;
    }
  }
  return lines;
}

/** Reads an SVG file (Buffer) into the shared vector shape (units unknown). */
export function readSvg(buffer) {
  let doc;
  try {
    const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '', preserveOrder: true, processEntities: false, parseTagValue: false, trimValues: true });
    doc = parser.parse(buffer.toString('utf8'));
  } catch (err) {
    throw new SvgError(`The SVG file could not be read (${String(err?.message ?? err).slice(0, 120)}).`);
  }
  const root = (doc ?? []).find((n) => Array.isArray(n.svg));
  if (!root) throw new SvgError('This file has no SVG drawing in it.');
  const c = new Collector();

  const walk = (nodes, m, depth, layerName) => {
    if (depth > MAX_DEPTH) return;
    for (const node of nodes) {
      const tag = Object.keys(node).find((k) => k !== ':@' && k !== '#text');
      if (!tag || SKIP.has(tag)) continue;
      const at = node[':@'] ?? {};
      if (at.display === 'none' || at.visibility === 'hidden') continue;
      const mm = at.transform ? multiply(m, parseTransform(at.transform)) : m;
      const layer = c.layer(layerName);
      const P = ([x, y]) => apply(mm, x, y);
      switch (tag) {
        case 'g':
        case 'svg':
        case 'a':
        case 'switch': {
          // A group's id or Inkscape label names the "layer" its lines belong to.
          const name = at['inkscape:label'] || at.id || layerName;
          walk(node[tag], mm, depth + 1, name);
          break;
        }
        case 'line':
          c.polyline([P([num(at.x1), num(at.y1)]), P([num(at.x2), num(at.y2)])], layer);
          break;
        case 'polyline':
          c.polyline(pointsAttr(at.points).map(P), layer);
          break;
        case 'polygon':
          c.polyline(pointsAttr(at.points).map(P), layer, true);
          break;
        case 'rect': {
          const x = num(at.x);
          const y = num(at.y);
          const w = num(at.width);
          const h = num(at.height);
          if (w > 0 && h > 0) c.polyline([[x, y], [x + w, y], [x + w, y + h], [x, y + h]].map(P), layer, true);
          break;
        }
        case 'circle': {
          const r = num(at.r);
          if (r > 0) c.polyline(arcPoints(num(at.cx), num(at.cy), r, 0, Math.PI * 2).map(P), layer);
          break;
        }
        case 'ellipse': {
          const rx = num(at.rx);
          const ry = num(at.ry);
          if (rx > 0 && ry > 0) {
            const pts = [];
            for (let i = 0; i <= 48; i++) {
              const u = (i / 48) * Math.PI * 2;
              pts.push(P([num(at.cx) + rx * Math.cos(u), num(at.cy) + ry * Math.sin(u)]));
            }
            c.polyline(pts, layer);
          }
          break;
        }
        case 'path':
          for (const line of pathPolylines(at.d)) if (line.length >= 2) c.polyline(line.map(P), layer);
          break;
        case 'text': {
          const p = P([num(at.x), num(at.y)]);
          c.text(p[0], p[1], textOf(node[tag]), layer);
          break;
        }
        default:
          break;
      }
    }
  };

  try {
    walk([root], IDENTITY, 0, 'default');
  } catch (err) {
    if (err instanceof TooComplex) throw new SvgError('This drawing is too complex to read (more than 400 000 lines).');
    throw err;
  }
  const out = c.result('svg', null);
  if (!out.bounds || out.segments.length === 0) throw new SvgError('No lines were found in the SVG drawing.');
  return out;
}
