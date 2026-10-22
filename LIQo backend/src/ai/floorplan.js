// AI floor-plan reading (Round 15). The model sees the plan, or a boxed part of
// it, with a light red reference grid and answers in JSON on a 0–1000 grid. Its
// answer is tidied up here (spec §10.4), mapped through the level's backdrop
// calibration into level metres, and returned as a proposal. Nothing is ever
// written to the draft from here.

import { PNG } from 'pngjs';
import { z } from 'zod';
import { SPACE_TYPES } from '../maps/catalog.js';
import { roomsFromWalls, nameRooms } from '../maps/measure.js';

export const MAX_SIDE = 2000;

// ---------------------------------------------------------------------------
// Picture preparation: crop → downscale → reference grid → PNG data: URL
// ---------------------------------------------------------------------------

/** Crop box in source pixels from fractions [x0,y0,x1,y1] (whole picture when absent). */
export function cropBox(width, height, crop) {
  const [fx0, fy0, fx1, fy1] = crop ?? [0, 0, 1, 1];
  const x0 = Math.max(0, Math.min(width - 1, Math.floor(Math.min(fx0, fx1) * width)));
  const y0 = Math.max(0, Math.min(height - 1, Math.floor(Math.min(fy0, fy1) * height)));
  const x1 = Math.max(x0 + 1, Math.min(width, Math.ceil(Math.max(fx0, fx1) * width)));
  const y1 = Math.max(y0 + 1, Math.min(height, Math.ceil(Math.max(fy0, fy1) * height)));
  return { x0, y0, w: x1 - x0, h: y1 - y0 };
}

/**
 * Cuts the box out of the decoded RGBA picture and scales it so its long side
 * is at most MAX_SIDE. Each output pixel mixes the average and the darkest
 * pixel under it, so thin ink lines stay visible after shrinking.
 */
export function cropAndScale(img, box) {
  const scale = Math.min(1, MAX_SIDE / Math.max(box.w, box.h));
  const ow = Math.max(1, Math.round(box.w * scale));
  const oh = Math.max(1, Math.round(box.h * scale));
  const out = new PNG({ width: ow, height: oh });
  const src = img.data;
  const fx = box.w / ow;
  const fy = box.h / oh;
  for (let y = 0; y < oh; y++) {
    const sy0 = box.y0 + Math.floor(y * fy);
    const sy1 = Math.max(sy0 + 1, box.y0 + Math.floor((y + 1) * fy));
    for (let x = 0; x < ow; x++) {
      const sx0 = box.x0 + Math.floor(x * fx);
      const sx1 = Math.max(sx0 + 1, box.x0 + Math.floor((x + 1) * fx));
      let r = 0, g = 0, b = 0, n = 0;
      let mr = 255, mg = 255, mb = 255;
      for (let sy = sy0; sy < sy1; sy++) {
        for (let sx = sx0; sx < sx1; sx++) {
          const o = (sy * img.width + sx) * 4;
          // Transparent pixels count as white paper.
          const a = src[o + 3] / 255;
          const pr = src[o] * a + 255 * (1 - a);
          const pg = src[o + 1] * a + 255 * (1 - a);
          const pb = src[o + 2] * a + 255 * (1 - a);
          r += pr; g += pg; b += pb; n += 1;
          if (pr < mr) mr = pr;
          if (pg < mg) mg = pg;
          if (pb < mb) mb = pb;
        }
      }
      const o = (y * ow + x) * 4;
      out.data[o] = Math.round((r / n + mr) / 2);
      out.data[o + 1] = Math.round((g / n + mg) / 2);
      out.data[o + 2] = Math.round((b / n + mb) / 2);
      out.data[o + 3] = 255;
    }
  }
  return out;
}

// 3×5 digits for the grid labels.
const DIGITS = {
  0: ['111', '101', '101', '101', '111'],
  1: ['010', '110', '010', '010', '111'],
  2: ['111', '001', '111', '100', '111'],
  3: ['111', '001', '111', '001', '111'],
  4: ['101', '101', '111', '001', '001'],
  5: ['111', '100', '111', '001', '111'],
  6: ['111', '100', '111', '101', '111'],
  7: ['111', '001', '001', '001', '001'],
  8: ['111', '101', '111', '101', '111'],
  9: ['111', '101', '111', '001', '111'],
};

const GRID_RGB = [225, 45, 45];

function blend(png, x, y, alpha) {
  if (x < 0 || y < 0 || x >= png.width || y >= png.height) return;
  const o = (y * png.width + x) * 4;
  for (let c = 0; c < 3; c++) png.data[o + c] = Math.round(png.data[o + c] * (1 - alpha) + GRID_RGB[c] * alpha);
}

function drawNumber(png, text, x, y, s) {
  // A white pad behind the digits keeps them readable over ink.
  const w = text.length * 4 * s;
  for (let yy = y - s; yy < y + 6 * s; yy++) {
    for (let xx = x - s; xx < x + w; xx++) {
      if (xx < 0 || yy < 0 || xx >= png.width || yy >= png.height) continue;
      const o = (yy * png.width + xx) * 4;
      png.data[o] = 255; png.data[o + 1] = 255; png.data[o + 2] = 255;
    }
  }
  [...text].forEach((ch, i) => {
    const rows = DIGITS[ch];
    if (!rows) return;
    for (let r = 0; r < 5; r++) {
      for (let c = 0; c < 3; c++) {
        if (rows[r][c] !== '1') continue;
        for (let dy = 0; dy < s; dy++) for (let dx = 0; dx < s; dx++) blend(png, x + (i * 4 + c) * s + dx, y + r * s + dy, 1);
      }
    }
  });
}

/**
 * A light red line every 50 of 1000 units, labelled every 100 along the top and
 * left edges (spec §10.1: without it the model rescales the building).
 */
export function drawGrid(png) {
  const long = Math.max(png.width, png.height);
  const lw = Math.max(1, Math.round(long / 1500));
  const s = Math.max(2, Math.round(long / 500));
  for (let k = 1; k < 20; k++) {
    const gx = Math.round((k / 20) * png.width);
    const gy = Math.round((k / 20) * png.height);
    const alpha = k % 2 === 0 ? 0.55 : 0.35;
    for (let t = 0; t < lw; t++) {
      for (let y = 0; y < png.height; y++) blend(png, gx + t, y, alpha);
      for (let x = 0; x < png.width; x++) blend(png, x, gy + t, alpha);
    }
  }
  for (let k = 1; k < 10; k++) {
    const label = String(k * 100);
    drawNumber(png, label, Math.round((k / 10) * png.width) + lw + s, s * 2, s);
    drawNumber(png, label, s * 2, Math.round((k / 10) * png.height) + lw + s, s);
  }
  return png;
}

/** The picture the model sees, as a data: URL, plus the crop box in source pixels. */
export function preparePicture(img, crop) {
  const box = cropBox(img.width, img.height, crop);
  const png = drawGrid(cropAndScale(img, box));
  const url = `data:image/png;base64,${PNG.sync.write(png).toString('base64')}`;
  return { url, box, sent: { width: png.width, height: png.height } };
}

// ---------------------------------------------------------------------------
// What the model is asked for
// ---------------------------------------------------------------------------

export const AI_SPACE_TYPES = SPACE_TYPES.filter((t) => t !== 'custom');
export const AI_WALL_KINDS = ['solid', 'glass', 'partition', 'boundary'];
export const AI_DOOR_KINDS = ['door', 'entrance', 'gate', 'shutter', 'passage'];

const point = { type: 'object', additionalProperties: false, required: ['x', 'y'], properties: { x: { type: 'number' }, y: { type: 'number' } } };

/** JSON Schema without unions, so every provider behind the gateway accepts it. */
export const ANSWER_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['isFloorPlan', 'outline', 'walls', 'doors', 'rooms', 'notes'],
  properties: {
    isFloorPlan: { type: 'boolean' },
    outline: { type: 'array', items: point },
    walls: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['x1', 'y1', 'x2', 'y2', 'kind', 'sure'],
        properties: { x1: { type: 'number' }, y1: { type: 'number' }, x2: { type: 'number' }, y2: { type: 'number' }, kind: { type: 'string', enum: AI_WALL_KINDS }, sure: { type: 'boolean' } },
      },
    },
    doors: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['x1', 'y1', 'x2', 'y2', 'kind', 'sure'],
        properties: { x1: { type: 'number' }, y1: { type: 'number' }, x2: { type: 'number' }, y2: { type: 'number' }, kind: { type: 'string', enum: AI_DOOR_KINDS }, sure: { type: 'boolean' } },
      },
    },
    rooms: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'type', 'polygon', 'sure'],
        properties: { name: { type: 'string' }, type: { type: 'string', enum: AI_SPACE_TYPES }, polygon: { type: 'array', items: point }, sure: { type: 'boolean' } },
      },
    },
    notes: { type: 'string' },
    // Round 16: for CAD drawings, the layers that hold walls (empty for pictures).
    wallLayers: { type: 'array', items: { type: 'string' } },
    // Round 18: one dimension written on the plan, to find the true scale.
    dimension: {
      type: 'object',
      additionalProperties: false,
      required: ['x1', 'y1', 'x2', 'y2', 'mm'],
      properties: { x1: { type: 'number' }, y1: { type: 'number' }, x2: { type: 'number' }, y2: { type: 'number' }, mm: { type: 'number' } },
    },
  },
};
ANSWER_SCHEMA.required.push('wallLayers', 'dimension');

export const SYSTEM_PROMPT = `You read architectural floor plans of shopping malls and return their geometry as JSON.

Coordinates: normalised picture coordinates, 0–1000 across (left to right) and 0–1000 down (top to bottom), whatever the picture's pixel size. A light red reference grid is drawn every 50 units and labelled every 100; use it to place points accurately. The grid is not part of the plan.

Return:
- isFloorPlan: false when the picture is not a floor plan (then leave every list empty and say why in notes).
- outline: the exterior wall centre-line of the floor as one polygon, following every step, notch and angle. Not a bounding box. Empty when the outer edge is not in the picture.
- walls: one straight segment per wall run, split at corners and junctions. Walls run straight through doorways; the doorway goes in doors. kind: boundary for exterior walls, solid for thick interior walls, partition for thin single-line walls between units, glass for shop fronts and glazing.
- doors: every opening people walk through, as the two ends of the gap along its wall (x1,y1 → x2,y2). kind: entrance for doors to the outside or mall entrances, shutter for shop fronts with roller shutters, gate for gates and turnstiles, passage for open gaps without a door, door otherwise.
- rooms: every enclosed unit or area as a polygon along its walls. name: the label written inside it exactly as printed (shop name or unit number), or "" when nothing readable is written. type: retail (shops and unlabelled units), food (restaurants, cafés, food court stalls), anchor (department stores, supermarkets, cinemas), service (banks, clinics, salons, services), office, storage (stock rooms, back of house, plant rooms), atrium (open atria and voids), corridor (malls, aisles and walkways), restroom, parking, outdoor.
- sure: false for anything you are not confident about (faint, partly hidden, guessed).
- notes: one or two short sentences about anything a person should check.
- wallLayers: only when the plan comes from a CAD drawing and its layer list is given: the names of the layers that hold the walls (copied exactly from the list). Otherwise an empty list.
- dimension: one measurement written on the plan, used to find its true scale. Prefer the longest overall dimension along the building's edge. Give the two ends of its dimension line exactly (where the tick marks or arrows are, x1,y1 → x2,y2 on the 0–1000 grid) and its value converted to millimetres (e.g. 11070 for "11070" on a plan in mm, 11070 for "11.07 m"). If no dimension is written, give mm 0.

Rules: dimension lines, labels, north arrows, legends, title blocks and empty paper outside the exterior walls are not part of the building. Leave out door swings, hatching, furniture, grid lines and text. Do not invent what you cannot see. If a store-name list is given, use it only to spell a name you can actually read on the plan.`;

export function userPrompt({ widthM, heightM, storeNames, partial, cad, scaleKnown = true }) {
  const lines = [
    scaleKnown
      ? `This picture ${partial ? 'is a part of' : 'shows'} a mall floor plan. In reality it is about ${widthM.toFixed(1)} m wide and ${heightM.toFixed(1)} m tall; use that to sanity-check your scale.`
      : `This picture ${partial ? 'is a part of' : 'shows'} a floor plan whose real size is not known yet; read the dimension carefully, it sets the scale.`,
    'Answer with the JSON object only.',
  ];
  if (partial) lines.push('Only report what is inside this picture; walls and rooms that run past its edge stop at the edge.');
  if (storeNames.length) lines.push(`Stores registered in this branch (for spelling only): ${storeNames.slice(0, 200).join('; ')}.`);
  if (cad) {
    // Round 16: a CAD drawing. Its walls will be laid on the exact CAD lines, so
    // the AI's job is to say which lines are walls and to name the rooms.
    lines.push('This plan comes from a CAD drawing; the picture shows its lines without text. Your walls will be laid onto the drawing\'s exact lines, so place them on the drawn walls.');
    if (cad.layers.length) lines.push(`Layers (name: number of lines): ${cad.layers.map((l) => `${l.name}: ${l.lines}`).join('; ')}. Put the layers that hold walls in wallLayers.`);
    if (cad.texts.length) lines.push(`Texts written in the drawing (x,y on the 0–1000 grid: text): ${cad.texts.map((t) => `${t.x},${t.y}: ${t.text}`).join(' | ')}. Use them for room names.`);
  }
  return lines.join('\n');
}

/**
 * What the AI is told about a CAD drawing: its layers (largest first) and the
 * texts inside the box, on the 0–1000 grid of the picture it sees.
 */
export function cadHints(vector, box) {
  const layers = (vector.layers ?? []).filter((l) => l.lines > 0).sort((a, b) => b.lines - a.lines).slice(0, 100);
  const texts = [];
  for (const t of vector.texts ?? []) {
    if (t.x < box.x0 || t.y < box.y0 || t.x > box.x0 + box.w || t.y > box.y0 + box.h) continue;
    texts.push({ x: Math.round(((t.x - box.x0) / box.w) * 1000), y: Math.round(((t.y - box.y0) / box.h) * 1000), text: t.text.replace(/[|;]/g, ' ').slice(0, 60) });
    if (texts.length >= 300) break;
  }
  return { layers, texts };
}

export function buildMessages({ pictureUrl, widthM, heightM, storeNames = [], partial = false, cad = null, scaleKnown = true }) {
  return [
    { role: 'system', content: SYSTEM_PROMPT },
    {
      role: 'user',
      content: [
        { type: 'text', text: userPrompt({ widthM, heightM, storeNames, partial, cad, scaleKnown }) },
        { type: 'image_url', image_url: { url: pictureUrl } },
      ],
    },
  ];
}

export const RESPONSE_FORMAT = { type: 'json_schema', json_schema: { name: 'floor_plan', strict: true, schema: ANSWER_SCHEMA } };

/** The schema without `additionalProperties`, which Gemini's schema support refuses. */
function relaxed(schema) {
  if (Array.isArray(schema)) return schema.map(relaxed);
  if (!schema || typeof schema !== 'object') return schema;
  const out = {};
  for (const [k, v] of Object.entries(schema)) if (k !== 'additionalProperties') out[k] = relaxed(v);
  return out;
}

/**
 * The answer formats to try, in order, for a model (seen 2026-10-22: Gemini
 * through the gateway refused the strict OpenAI-style schema with "Request
 * contains an invalid argument"). OpenAI models start with the strict schema;
 * others with the relaxed one. If the provider still refuses the format, the
 * reading falls back to plain JSON (the prompt describes every field).
 */
export function responseFormats(model) {
  const relaxedFormat = { type: 'json_schema', json_schema: { name: 'floor_plan', schema: relaxed(ANSWER_SCHEMA) } };
  const plain = { type: 'json_object' };
  return /^(gpt-|o\d)/i.test(model) ? [RESPONSE_FORMAT, relaxedFormat, plain] : [relaxedFormat, plain];
}

// ---------------------------------------------------------------------------
// Reading the answer
// ---------------------------------------------------------------------------

const unit = z.coerce.number().finite().transform((n) => Math.min(1000, Math.max(0, n)));
const pt = z.object({ x: unit, y: unit });
const answerShape = z.object({
  isFloorPlan: z.boolean().catch(true),
  outline: z.array(pt).catch([]),
  walls: z.array(z.object({ x1: unit, y1: unit, x2: unit, y2: unit, kind: z.enum(AI_WALL_KINDS).catch('solid'), sure: z.boolean().catch(true) })).catch([]),
  doors: z.array(z.object({ x1: unit, y1: unit, x2: unit, y2: unit, kind: z.enum(AI_DOOR_KINDS).catch('door'), sure: z.boolean().catch(true) })).catch([]),
  rooms: z.array(z.object({ name: z.string().catch(''), type: z.enum(AI_SPACE_TYPES).catch('retail'), polygon: z.array(pt), sure: z.boolean().catch(true) })).catch([]),
  notes: z.string().catch(''),
  wallLayers: z.array(z.string()).catch([]),
  dimension: z.object({ x1: unit, y1: unit, x2: unit, y2: unit, mm: z.coerce.number().finite() }).nullable().catch(null),
});

/** Parses the model's text. Returns null when it is not the expected JSON. */
export function parseAnswer(text) {
  if (typeof text !== 'string') return null;
  let t = text.trim();
  const fence = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(t);
  if (fence) t = fence[1];
  const first = t.indexOf('{');
  const last = t.lastIndexOf('}');
  if (first < 0 || last <= first) return null;
  let json;
  try {
    json = JSON.parse(t.slice(first, last + 1));
  } catch {
    return null;
  }
  if (!json || typeof json !== 'object' || Array.isArray(json)) return null;
  const r = answerShape.safeParse(json);
  return r.success ? r.data : null;
}

// ---------------------------------------------------------------------------
// Tidy-up (spec §10.4), in picture metres, then into level metres
// ---------------------------------------------------------------------------

const MIN_WALL = 0.3;
const STRAIGHTEN_DEG = 4;
const SNAP = 0.25;
const SHARE_LINE = 0.15;
const DOOR_REACH = 0.6;
const MIN_ROOM = 1;
const THICKNESS = { boundary: 0.3, solid: 0.2, partition: 0.1, glass: 0.1 };

const r3 = (n) => Math.round(n * 1000) / 1000;
const len = (w) => Math.hypot(w.b[0] - w.a[0], w.b[1] - w.a[1]);

function ringArea(ring) {
  let a = 0;
  for (let i = 0; i < ring.length; i++) {
    const [x1, y1] = ring[i];
    const [x2, y2] = ring[(i + 1) % ring.length];
    a += x1 * y2 - x2 * y1;
  }
  return Math.abs(a) / 2;
}

function cleanRing(ring) {
  const out = [];
  for (const p of ring) {
    const last = out[out.length - 1];
    if (!last || Math.hypot(p[0] - last[0], p[1] - last[1]) > 0.05) out.push(p);
  }
  if (out.length > 2 && Math.hypot(out[0][0] - out[out.length - 1][0], out[0][1] - out[out.length - 1][1]) <= 0.05) out.pop();
  return out;
}

function axisOf(w) {
  const deg = (Math.atan2(Math.abs(w.b[1] - w.a[1]), Math.abs(w.b[0] - w.a[0])) * 180) / Math.PI;
  if (deg <= STRAIGHTEN_DEG) return 'h';
  if (deg >= 90 - STRAIGHTEN_DEG) return 'v';
  return null;
}

/**
 * Puts near-horizontal and near-vertical walls on exact shared lines (weighted
 * by length). Walls taken from CAD lines (`exact`) set the line and never move.
 */
function straighten(walls) {
  for (const axis of ['h', 'v']) {
    const k = axis === 'h' ? 1 : 0; // the fixed coordinate
    const group = walls.filter((w) => w.axis === axis).map((w) => ({ w, pos: (w.a[k] + w.b[k]) / 2, weight: len(w) }));
    group.sort((p, q) => p.pos - q.pos);
    let i = 0;
    while (i < group.length) {
      let j = i + 1;
      while (j < group.length && group[j].pos - group[j - 1].pos <= SHARE_LINE) j++;
      const slice = group.slice(i, j);
      const exact = slice.filter((g) => g.w.exact);
      const basis = exact.length ? exact : slice;
      const total = basis.reduce((s, g) => s + g.weight, 0) || 1;
      const line = basis.reduce((s, g) => s + g.pos * g.weight, 0) / total;
      for (const g of slice) {
        if (g.w.exact) continue;
        g.w.a[k] = line;
        g.w.b[k] = line;
      }
      i = j;
    }
  }
  // Each straight wall runs low → high along its own axis.
  for (const w of walls) {
    const k = w.axis === 'h' ? 0 : w.axis === 'v' ? 1 : -1;
    if (k >= 0 && w.a[k] > w.b[k]) [w.a, w.b] = [w.b, w.a];
  }
}

/** Closes corners and T-junctions by moving ends along their own line; joins loose diagonal ends. */
function snapEnds(walls) {
  const hs = walls.filter((w) => w.axis === 'h');
  const vs = walls.filter((w) => w.axis === 'v');
  for (const h of hs) {
    for (const end of [h.a, h.b]) {
      let best = null;
      for (const v of vs) {
        const d = Math.abs(end[0] - v.a[0]);
        if (d <= SNAP && end[1] >= v.a[1] - SNAP && end[1] <= v.b[1] + SNAP && (!best || d < best.d)) best = { d, x: v.a[0] };
      }
      if (best) end[0] = best.x;
    }
  }
  for (const v of vs) {
    for (const end of [v.a, v.b]) {
      let best = null;
      for (const h of hs) {
        const d = Math.abs(end[1] - h.a[1]);
        if (d <= SNAP && end[0] >= h.a[0] - SNAP && end[0] <= h.b[0] + SNAP && (!best || d < best.d)) best = { d, y: h.a[1] };
      }
      if (best) end[1] = best.y;
    }
  }
  // Diagonal ends jump to a nearby end; exact (CAD) diagonals stay on their line.
  for (const w of walls.filter((x) => !x.axis && !x.exact)) {
    for (const end of [w.a, w.b]) {
      let best = null;
      for (const o of walls) {
        if (o === w) continue;
        for (const e of [o.a, o.b]) {
          const d = Math.hypot(e[0] - end[0], e[1] - end[1]);
          if (d <= SNAP && (!best || d < best.d)) best = { d, e };
        }
      }
      if (best) {
        end[0] = best.e[0];
        end[1] = best.e[1];
      }
    }
  }
}

/** Overlapping copies of the same straight wall become one. */
function mergeCopies(walls) {
  const out = [];
  for (const w of walls) {
    const k = w.axis === 'h' ? 0 : w.axis === 'v' ? 1 : -1;
    const other = k < 0 ? -1 : 1 - k;
    const twin = k < 0 ? null : out.find((o) => o.axis === w.axis && Math.abs(o.a[other] - w.a[other]) < 0.01 && Math.min(o.b[k], w.b[k]) - Math.max(o.a[k], w.a[k]) > 0.1);
    if (!twin) {
      out.push(w);
      continue;
    }
    twin.a[k] = Math.min(twin.a[k], w.a[k]);
    twin.b[k] = Math.max(twin.b[k], w.b[k]);
    if (len(w) > len(twin)) twin.kind = w.kind;
    twin.sure = twin.sure && w.sure;
    // A CAD-exact copy wins: its line and thickness are the true ones.
    if (w.exact && !twin.exact) {
      twin.exact = true;
      twin.t = w.t;
      twin.sure = true;
    }
  }
  return out;
}

function nearestOnWall(walls, p) {
  let best = null;
  for (const w of walls) {
    const dx = w.b[0] - w.a[0];
    const dy = w.b[1] - w.a[1];
    const l2 = dx * dx + dy * dy;
    if (l2 === 0) continue;
    const t = Math.max(0, Math.min(1, ((p[0] - w.a[0]) * dx + (p[1] - w.a[1]) * dy) / l2));
    const d = Math.hypot(w.a[0] + dx * t - p[0], w.a[1] + dy * t - p[1]);
    if (!best || d < best.d) best = { w, t, d };
  }
  return best;
}

/**
 * Turns the parsed answer into a proposal in level metres.
 * @param answer   parsed model answer (0–1000 units)
 * @param box      crop box in source pixels {x0,y0,w,h}
 * @param image    {width,height} of the whole source picture
 * @param calib    level backdrop {cx,cz,mpp,rot}
 * @param newId    id maker (prefix → id)
 */
export function toProposal(answer, { box, image, calib, newId, cad = null }) {
  const mpp = calib.mpp;
  // 0–1000 → picture metres (unrotated, from the picture's top-left).
  const pm = (x, y) => [(box.x0 + (x / 1000) * box.w) * mpp, (box.y0 + (y / 1000) * box.h) * mpp];
  const rad = (calib.rot * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  const halfW = (image.width * mpp) / 2;
  const halfH = (image.height * mpp) / 2;
  const toLevel = ([x, y]) => {
    const mx = x - halfW;
    const mz = y - halfH;
    return [r3(calib.cx + mx * cos - mz * sin), r3(calib.cz + mx * sin + mz * cos)];
  };

  // Walls in picture metres, tidied up there (a plan's walls are square to the picture).
  let walls = answer.walls
    .map((w) => ({ a: pm(w.x1, w.y1), b: pm(w.x2, w.y2), kind: w.kind, sure: w.sure }))
    .filter((w) => len(w) >= MIN_WALL);
  // A CAD drawing (Round 16): the AI's walls are laid on the drawing's exact lines.
  const cadSegs = cad ? cadSegments(cad, mpp, box) : null;
  if (cadSegs) walls = snapToCad(walls, cadSegs, new Set(answer.wallLayers ?? []));
  const exactWalls = walls.filter((w) => w.exact).length;
  for (const w of walls) w.axis = axisOf(w);
  straighten(walls);
  snapEnds(walls);
  walls = mergeCopies(walls).filter((w) => len(w) >= MIN_WALL);

  const uncertain = [];
  const outWalls = walls.map((w) => {
    const id = newId('ai-w');
    w.id = id;
    if (!w.sure) uncertain.push(id);
    return { id, a: toLevel(w.a), b: toLevel(w.b), t: r3(Math.min(2, Math.max(0.05, w.t ?? THICKNESS[w.kind] ?? 0.2))), kind: w.kind };
  });

  // Doors onto the nearest wall within reach; width kept inside the wall.
  const openings = [];
  for (const d of answer.doors) {
    const p1 = pm(d.x1, d.y1);
    const p2 = pm(d.x2, d.y2);
    const mid = [(p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2];
    const hit = nearestOnWall(walls, mid);
    if (!hit || hit.d > DOOR_REACH) continue;
    const wallLen = len(hit.w);
    let width = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    if (!(width >= 0.3)) width = 0.9;
    width = Math.min(Math.max(width, 0.6), 12, wallLen);
    if (width < 0.4) continue;
    const half = width / 2 / wallLen;
    const at = Math.min(1 - half, Math.max(half, hit.t));
    const clash = openings.some((o) => o.wall === hit.w.id && Math.abs(o.at - at) * wallLen < (o.w + width) / 2);
    if (clash) continue;
    const id = newId('ai-o');
    if (!d.sure) uncertain.push(id);
    openings.push({ id, wall: hit.w.id, at: r3(at), w: r3(width), kind: d.kind });
  }

  const spaces = [];
  for (const r of answer.rooms) {
    const ring = cleanRing(r.polygon.map((p) => pm(p.x, p.y)));
    if (ring.length < 3 || ringArea(ring) < MIN_ROOM) continue;
    const id = newId('ai-sp');
    if (!r.sure) uncertain.push(id);
    let name = r.name.trim().slice(0, 80);
    // The drawing's own spelling wins when a text inside the room reads like the AI's name.
    if (cad && name) {
      let best = null;
      for (const t of cad.texts ?? []) {
        const p = [t.x * mpp, t.y * mpp];
        if (!pointInRing(p, ring)) continue;
        const score = nameSimilarity(name, t.text);
        if (score >= MATCH_AT && (!best || score > best.score)) best = { score, text: t.text };
      }
      if (best) name = best.text.slice(0, 80);
    }
    spaces.push({ id, name, type: r.type, shape: { outer: ring.map(toLevel), holes: [] } });
  }

  let outline = null;
  const ring = cleanRing(answer.outline.map((p) => pm(p.x, p.y)));
  if (ring.length >= 3 && ringArea(ring) >= MIN_ROOM) outline = { outer: ring.map(toLevel), holes: [] };

  return { walls: outWalls, openings, spaces, outline, uncertain, exactWalls };
}

function pointInRing([x, y], ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// ---------------------------------------------------------------------------
// Exact walls from CAD lines (Round 16, owner decision: "exact lines + AI for
// names", the AI picks which lines are walls)
// ---------------------------------------------------------------------------

const CAD_ANGLE = Math.sin((4 * Math.PI) / 180);
const CAD_REACH = 0.4;
const FACE_MIN = 0.06;
const FACE_MAX = 0.28;
const MAX_MISSED = 8000;

/** The drawing's lines in picture metres, with their layer names (near the box only). */
function cadSegments(cad, mpp, box) {
  const names = (cad.layers ?? []).map((l) => l.name);
  const s = cad.segments ?? [];
  const pad = 2 / mpp; // 2 m around the box, in pixels
  const out = [];
  for (let i = 0; i < s.length; i += 5) {
    const [x1, y1, x2, y2] = [s[i], s[i + 1], s[i + 2], s[i + 3]];
    if (Math.max(x1, x2) < box.x0 - pad || Math.min(x1, x2) > box.x0 + box.w + pad || Math.max(y1, y2) < box.y0 - pad || Math.min(y1, y2) > box.y0 + box.h + pad) continue;
    const a = [x1 * mpp, y1 * mpp];
    const b = [x2 * mpp, y2 * mpp];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (l < 0.05) continue;
    out.push({ a, b, len: l, ux: (b[0] - a[0]) / l, uy: (b[1] - a[1]) / l, layer: names[s[i + 4]] ?? '' });
  }
  return out;
}

/** Wall faces among lines: groups of nearly equal offset (within 2 cm), with how much of the wall they cover. */
function faceGroups(cands, L) {
  cands.sort((p, q) => p.off - q.off);
  const groups = [];
  for (const c of cands) {
    const g = groups[groups.length - 1];
    if (g && c.off - g.last <= 0.02) {
      g.items.push(c);
      g.last = c.off;
    } else groups.push({ items: [c], last: c.off });
  }
  for (const g of groups) {
    const cover = g.items.reduce((n, c) => n + Math.max(0, Math.min(c.hi, L) - Math.max(c.lo, 0)), 0);
    const weight = g.items.reduce((n, c) => n + c.len, 0) || 1;
    g.off = g.items.reduce((n, c) => n + c.off * c.len, 0) / weight;
    g.cover = cover;
  }
  return groups;
}

/**
 * Lays each AI wall onto the matching CAD lines: near-parallel (within 4°),
 * within 40 cm, covering at least half of it. Two faces 6–28 cm apart give the
 * centre line and the true thickness; one line is used as drawn. Lines on the
 * layers the AI named as walls that no wall covers are added too.
 */
export function snapToCad(aiWalls, segs, wallLayers) {
  const used = new Set();
  const out = [];
  const preferred = wallLayers.size > 0;
  for (const w of aiWalls) {
    const L = len(w);
    const ux = (w.b[0] - w.a[0]) / L;
    const uy = (w.b[1] - w.a[1]) / L;
    let cands = [];
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i];
      if (Math.abs(ux * s.uy - uy * s.ux) > CAD_ANGLE) continue;
      const d1 = (s.a[0] - w.a[0]) * -uy + (s.a[1] - w.a[1]) * ux;
      const d2 = (s.b[0] - w.a[0]) * -uy + (s.b[1] - w.a[1]) * ux;
      if (Math.abs(d1) > CAD_REACH || Math.abs(d2) > CAD_REACH) continue;
      const t1 = (s.a[0] - w.a[0]) * ux + (s.a[1] - w.a[1]) * uy;
      const t2 = (s.b[0] - w.a[0]) * ux + (s.b[1] - w.a[1]) * uy;
      const lo = Math.min(t1, t2);
      const hi = Math.max(t1, t2);
      if (Math.min(hi, L) - Math.max(lo, 0) <= 0) continue;
      cands.push({ i, s, off: (d1 + d2) / 2, lo, hi, len: s.len, pref: wallLayers.has(s.layer) });
    }
    if (preferred && cands.some((c) => c.pref)) cands = cands.filter((c) => c.pref);
    const groups = faceGroups(cands, L).filter((g) => g.cover >= 0.3 * L);
    if (!groups.length) {
      out.push(w);
      continue;
    }
    // Best pair of faces: both cover well, the right distance apart, around the AI's line.
    let pick = null;
    for (let i = 0; i < groups.length; i++) {
      for (let j = i + 1; j < groups.length; j++) {
        const sep = groups[j].off - groups[i].off;
        if (sep < FACE_MIN || sep > FACE_MAX) continue;
        const score = Math.min(groups[i].cover, groups[j].cover) - Math.abs((groups[i].off + groups[j].off) / 2) * L;
        if (!pick || score > pick.score) pick = { score, faces: [groups[i], groups[j]], off: (groups[i].off + groups[j].off) / 2, t: sep };
      }
    }
    if (!pick) {
      const g = groups.reduce((a, b) => (b.cover > a.cover || (b.cover === a.cover && Math.abs(b.off) < Math.abs(a.off)) ? b : a));
      pick = { faces: [g], off: g.off, t: null };
    }
    const items = pick.faces.flatMap((g) => g.items);
    const coverAll = pick.faces.reduce((n, g) => n + g.cover, 0) / pick.faces.length;
    if (coverAll < 0.5 * L) {
      out.push(w);
      continue;
    }
    for (const c of items) used.add(c.i);
    // Everything from here is measured on the drawing itself: the direction of
    // its longest line (pointing the AI wall's way), each face's offset from that
    // line, and the extent of the face lines, kept within half a metre of the AI wall.
    const longest = items.reduce((a, b) => (b.len > a.len ? b : a)).s;
    const sign = longest.ux * ux + longest.uy * uy < 0 ? -1 : 1;
    const dx = longest.ux * sign;
    const dy = longest.uy * sign;
    const R = longest.a;
    const offOf = (p) => (p[0] - R[0]) * -dy + (p[1] - R[1]) * dx;
    const along = (p) => (p[0] - R[0]) * dx + (p[1] - R[1]) * dy;
    const faceOff = pick.faces.map((g) => {
      const weight = g.items.reduce((n, c) => n + c.len, 0) || 1;
      return g.items.reduce((n, c) => n + ((offOf(c.s.a) + offOf(c.s.b)) / 2) * c.len, 0) / weight;
    });
    const centre = faceOff.reduce((n, x) => n + x, 0) / faceOff.length;
    const ta = along(w.a);
    const tb = along(w.b);
    const ends = items.flatMap((c) => [along(c.s.a), along(c.s.b)]);
    const lo = Math.max(Math.min(ta, tb) - 0.5, Math.min(...ends));
    const hi = Math.min(Math.max(ta, tb) + 0.5, Math.max(...ends));
    const base = [R[0] - dy * centre, R[1] + dx * centre];
    const t = pick.faces.length === 2 ? Math.abs(faceOff[1] - faceOff[0]) : null;
    out.push({ a: [base[0] + dx * lo, base[1] + dy * lo], b: [base[0] + dx * hi, base[1] + dy * hi], kind: w.kind, sure: true, exact: true, t: t ?? THICKNESS[w.kind] ?? 0.2 });
  }

  // Lines on the AI's wall layers that no wall took: pairs of faces, or long single lines.
  if (preferred) {
    const covered = (s) =>
      out.some((w) => {
        const L = len(w);
        const ux = (w.b[0] - w.a[0]) / L;
        const uy = (w.b[1] - w.a[1]) / L;
        if (Math.abs(ux * s.uy - uy * s.ux) > CAD_ANGLE) return false;
        const d = Math.abs((s.a[0] - w.a[0]) * -uy + (s.a[1] - w.a[1]) * ux);
        if (d > 0.3) return false;
        const t1 = (s.a[0] - w.a[0]) * ux + (s.a[1] - w.a[1]) * uy;
        const t2 = (s.b[0] - w.a[0]) * ux + (s.b[1] - w.a[1]) * uy;
        return Math.min(Math.max(t1, t2), L) - Math.max(Math.min(t1, t2), 0) > 0.5 * s.len;
      });
    const left = [];
    for (let i = 0; i < segs.length && left.length < MAX_MISSED; i++) {
      const s = segs[i];
      if (used.has(i) || !wallLayers.has(s.layer) || s.len < 0.3 || covered(s)) continue;
      left.push(s);
    }
    const taken = new Set();
    for (let i = 0; i < left.length; i++) {
      if (taken.has(i)) continue;
      const s = left[i];
      let best = null;
      for (let j = 0; j < left.length; j++) {
        if (j === i || taken.has(j)) continue;
        const o = left[j];
        if (Math.abs(s.ux * o.uy - s.uy * o.ux) > Math.sin((2 * Math.PI) / 180)) continue;
        const mid = [(o.a[0] + o.b[0]) / 2, (o.a[1] + o.b[1]) / 2];
        const sep = (mid[0] - s.a[0]) * -s.uy + (mid[1] - s.a[1]) * s.ux;
        if (Math.abs(sep) < FACE_MIN || Math.abs(sep) > FACE_MAX) continue;
        const t1 = (o.a[0] - s.a[0]) * s.ux + (o.a[1] - s.a[1]) * s.uy;
        const t2 = (o.b[0] - s.a[0]) * s.ux + (o.b[1] - s.a[1]) * s.uy;
        const lo = Math.max(0, Math.min(t1, t2));
        const hi = Math.min(s.len, Math.max(t1, t2));
        if (hi - lo < 0.5) continue;
        if (!best || hi - lo > best.hi - best.lo) best = { j, sep, lo, hi };
      }
      if (best) {
        taken.add(i);
        taken.add(best.j);
        const off = best.sep / 2;
        const base = [s.a[0] - s.uy * off, s.a[1] + s.ux * off];
        out.push({ a: [base[0] + s.ux * best.lo, base[1] + s.uy * best.lo], b: [base[0] + s.ux * best.hi, base[1] + s.uy * best.hi], kind: 'solid', sure: true, exact: true, t: Math.abs(best.sep) });
      }
    }
    for (let i = 0; i < left.length; i++) {
      if (taken.has(i) || left[i].len < 1) continue;
      const s = left[i];
      out.push({ a: [...s.a], b: [...s.b], kind: 'partition', sure: true, exact: true, t: THICKNESS.partition });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Matching room names to the branch's stores
// ---------------------------------------------------------------------------

export function normaliseName(s) {
  return String(s ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '') // accents
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function editDistance(a, b) {
  if (a === b) return 0;
  const prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let diag = prev[0];
    prev[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const keep = prev[j];
      prev[j] = Math.min(prev[j] + 1, prev[j - 1] + 1, diag + (a[i - 1] === b[j - 1] ? 0 : 1));
      diag = keep;
    }
  }
  return prev[b.length];
}

/** How alike two names are, 0–1 (case, accents and punctuation ignored). */
export function nameSimilarity(a, b) {
  const x = normaliseName(a);
  const y = normaliseName(b);
  if (!x || !y) return 0;
  if (x === y) return 1;
  const sx = x.replace(/ /g, '');
  const sy = y.replace(/ /g, '');
  if (sx === sy) return 0.98;
  // "Jollibee" inside "Jollibee Express": a strong but not exact match.
  const [short, long] = sx.length <= sy.length ? [sx, sy] : [sy, sx];
  if (short.length >= 4 && long.includes(short)) return 0.9;
  return 1 - editDistance(sx, sy) / Math.max(sx.length, sy.length);
}

export const MATCH_AT = 0.8;

/** Each named space gets its best store at or above MATCH_AT. */
export function matchStores(spaces, stores) {
  const out = [];
  for (const s of spaces) {
    if (!s.name) continue;
    let best = null;
    for (const st of stores) {
      const score = nameSimilarity(s.name, st.name);
      if (score >= MATCH_AT && (!best || score > best.score)) best = { score, st };
    }
    if (best) out.push({ spaceId: s.id, storeId: best.st.id, storeName: best.st.name, exact: best.score >= 0.98 });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Measured walls + AI names (Round 18, owner decision 2026-10-22)
// ---------------------------------------------------------------------------

const segLen = (w) => Math.hypot(w.b[0] - w.a[0], w.b[1] - w.a[1]);

/** Is the AI wall lying along a measured one (near-parallel, close, mostly overlapping)? */
function coveredBy(w, walls) {
  const L = segLen(w);
  if (L === 0) return true;
  const ux = (w.b[0] - w.a[0]) / L;
  const uy = (w.b[1] - w.a[1]) / L;
  return walls.some((m) => {
    const ML = segLen(m);
    if (ML === 0) return false;
    const mx = (m.b[0] - m.a[0]) / ML;
    const my = (m.b[1] - m.a[1]) / ML;
    if (Math.abs(ux * my - uy * mx) > Math.sin((6 * Math.PI) / 180)) return false;
    const d1 = Math.abs((w.a[0] - m.a[0]) * -my + (w.a[1] - m.a[1]) * mx);
    const d2 = Math.abs((w.b[0] - m.a[0]) * -my + (w.b[1] - m.a[1]) * mx);
    if (Math.max(d1, d2) > 0.4) return false;
    const t1 = (w.a[0] - m.a[0]) * mx + (w.a[1] - m.a[1]) * my;
    const t2 = (w.b[0] - m.a[0]) * mx + (w.b[1] - m.a[1]) * my;
    return Math.min(Math.max(t1, t2), ML) - Math.max(Math.min(t1, t2), 0) >= 0.5 * L;
  });
}

/**
 * Trims or stretches an AI wall's ends onto the measured walls they run into
 * (within 40 cm), so an AI wall never pokes through a measured one or stops
 * just short of it.
 */
function meetMeasured(w, measured) {
  for (const endA of [true, false]) {
    const end = endA ? w.a : w.b;
    const other = endA ? w.b : w.a;
    const dx = end[0] - other[0];
    const dy = end[1] - other[1];
    const L = Math.hypot(dx, dy);
    if (L === 0) continue;
    let best = null;
    for (const m of measured) {
      const ex = m.b[0] - m.a[0];
      const ey = m.b[1] - m.a[1];
      const den = dx * ey - dy * ex;
      if (Math.abs(den) < 1e-9 * L * Math.hypot(ex, ey)) continue; // parallel
      // other + t·(end − other) = m.a + s·(m.b − m.a)
      const t = ((m.a[0] - other[0]) * ey - (m.a[1] - other[1]) * ex) / den;
      const s = ((m.a[0] - other[0]) * dy - (m.a[1] - other[1]) * dx) / den;
      const ML = Math.hypot(ex, ey);
      const move = Math.abs((t - 1) * L);
      if (move > 0.4 || s < -0.3 / ML || s > 1 + 0.3 / ML || t <= 0.5) continue;
      if (!best || move < best.move) best = { move, x: other[0] + t * dx, y: other[1] + t * dy };
    }
    if (best) {
      end[0] = r3(best.x);
      end[1] = r3(best.y);
    }
  }
}

function nearRing(p, ring, margin) {
  if (pointInRing(p, ring)) return true;
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i];
    const b = ring[(i + 1) % ring.length];
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const l2 = dx * dx + dy * dy || 1;
    const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2));
    if (Math.hypot(a[0] + dx * t - p[0], a[1] + dy * t - p[1]) <= margin) return true;
  }
  return false;
}

/**
 * Joins the measured walls with the AI's reading (both in level metres):
 * measured walls are the walls (exact, sure); AI walls that no measured wall
 * covers (glass, thin partitions) are added; measured walls outside the AI's
 * floor outline (+1 m: dimension lines, title block) are dropped; doors are the
 * measured gaps plus the AI's doors on the nearest wall, without doubles.
 */
export function mergeMeasured(ai, measured, { newId }) {
  const ring = ai.outline?.outer;
  const inside = (w) => !ring || nearRing(w.a, ring, 1) || nearRing(w.b, ring, 1);
  const walls = [];
  const openings = [];
  for (const m of measured.walls) {
    if (!inside(m)) continue;
    const id = newId('ai-w');
    walls.push({ id, a: m.a, b: m.b, t: m.t, kind: 'solid' });
    for (const o of m.openings) openings.push({ id: newId('ai-o'), wall: id, at: o.at, w: o.w, kind: 'door' });
  }
  const uncertain = new Set(ai.uncertain);
  const measuredOnly = walls.slice();
  const kept = [];
  for (const w of ai.walls) {
    if (coveredBy(w, walls)) continue;
    meetMeasured(w, measuredOnly);
    kept.push(w);
    walls.push(w);
  }
  // AI doors onto the nearest merged wall; a door already measured there takes the AI's kind.
  const aiWallById = new Map(ai.walls.map((w) => [w.id, w]));
  for (const o of ai.openings) {
    const w0 = aiWallById.get(o.wall);
    if (!w0) continue;
    const mid = [w0.a[0] + (w0.b[0] - w0.a[0]) * o.at, w0.a[1] + (w0.b[1] - w0.a[1]) * o.at];
    let best = null;
    for (const w of walls) {
      const L = segLen(w);
      if (L === 0) continue;
      const t = Math.max(0, Math.min(1, ((mid[0] - w.a[0]) * (w.b[0] - w.a[0]) + (mid[1] - w.a[1]) * (w.b[1] - w.a[1])) / (L * L)));
      const d = Math.hypot(w.a[0] + (w.b[0] - w.a[0]) * t - mid[0], w.a[1] + (w.b[1] - w.a[1]) * t - mid[1]);
      if (d <= 0.6 && (!best || d < best.d)) best = { w, t, d, L };
    }
    if (!best) continue;
    const same = openings.find((x) => x.wall === best.w.id && Math.abs(x.at - best.t) * best.L < 0.5);
    if (same) {
      same.kind = o.kind;
      continue;
    }
    const width = Math.min(o.w, best.L);
    const half = width / 2 / best.L;
    const at = Math.min(1 - half, Math.max(half, best.t));
    if (openings.some((x) => x.wall === best.w.id && Math.abs(x.at - at) * best.L < (x.w + width) / 2)) continue;
    openings.push({ ...o, wall: best.w.id, at: r3(at), w: r3(width) });
  }
  const keptIds = new Set([...kept.map((w) => w.id), ...openings.map((o) => o.id), ...ai.spaces.map((s) => s.id)]);
  return {
    ...ai,
    walls,
    openings,
    uncertain: [...uncertain].filter((id) => keptIds.has(id)),
    measuredWalls: walls.length - kept.length,
  };
}

/**
 * Rooms shaped by the walls (owner decision 2026-10-22): the areas the walls
 * enclose become the rooms; the AI's names and types are attached to the room
 * their label covers; the edge of everything inside becomes the floor outline.
 * AI rooms that fall in no enclosed area (open halls) are kept as the AI drew them.
 */
export function shapeRooms(p, { newId }) {
  const filled = roomsFromWalls(p.walls);
  if (!filled.rooms.length) return p;
  const pick = nameRooms(filled, p.spaces.map((s) => s.shape.outer));
  const uncertain = new Set(p.uncertain);
  const used = new Set();
  const spaces = filled.rooms.map((r, i) => {
    const ai = pick[i] >= 0 ? p.spaces[pick[i]] : null;
    const id = ai && !used.has(ai.id) ? ai.id : newId('ai-sp');
    if (ai) used.add(ai.id);
    if (!ai) uncertain.add(id);
    return { id, name: ai?.name ?? '', type: ai?.type ?? 'retail', shape: { outer: r.outer, holes: [] } };
  });
  // AI rooms outside every enclosed area stay as drawn (marked as they were).
  for (const s of p.spaces) {
    if (used.has(s.id)) continue;
    const ring = s.shape.outer;
    let cx = 0;
    let cz = 0;
    for (const [x, z] of ring) {
      cx += x;
      cz += z;
    }
    const c = [cx / ring.length, cz / ring.length];
    if (filled.rooms.some((r) => pointInRing(c, r.outer))) continue;
    spaces.push(s);
  }
  const ids = new Set([...p.walls.map((w) => w.id), ...p.openings.map((o) => o.id), ...spaces.map((s) => s.id)]);
  return {
    ...p,
    spaces,
    outline: filled.outline ? { outer: filled.outline, holes: [] } : p.outline,
    uncertain: [...uncertain].filter((id) => ids.has(id)),
    roomsFromWalls: filled.rooms.length,
  };
}

/**
 * The true scale from the dimension the AI read (Round 18, owner decision:
 * "AI finds the scale itself"): metres per source pixel, or null when there is
 * no usable dimension (none read, too short to trust, or a result no floor plan
 * could have).
 */
export function scaleFromDimension(dimension, box, image) {
  if (!dimension || !(dimension.mm > 100)) return null;
  const dx = ((dimension.x2 - dimension.x1) / 1000) * box.w;
  const dy = ((dimension.y2 - dimension.y1) / 1000) * box.h;
  const px = Math.hypot(dx, dy);
  if (px < Math.max(40, 0.08 * Math.max(box.w, box.h))) return null;
  const mpp = dimension.mm / 1000 / px;
  const width = image.width * mpp;
  if (mpp < 0.0001 || mpp > 1 || width < 3 || width > 3000) return null;
  return Math.round(mpp * 1e7) / 1e7;
}
