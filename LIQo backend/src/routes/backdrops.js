import { Router } from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import multer from 'multer';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../middleware/errors.js';
import { recordAudit } from '../middleware/audit.js';
import * as backdrops from '../repos/backdrops.js';
import * as maps from '../repos/maps.js';
import * as branches from '../repos/branches.js';
import * as settings from '../repos/settings.js';
import { resolveScope, assertBranchInScope } from '../utils/scope.js';
import * as stores from '../repos/stores.js';
import * as gateway from '../ai/gateway.js';
import * as creditOps from '../ai/creditOps.js';
import { preparePicture, buildMessages, responseFormats, parseAnswer, toProposal, matchStores, cadHints, mergeMeasured, shapeRooms, scaleFromDimension } from '../ai/floorplan.js';
import { sniffMime, imageSize, decodeImage } from '../maps/image.js';
import { measurePlan } from '../maps/measure.js';
import { validateLayout } from '../maps/validator.js';
import { newId } from '../maps/ids.js';
import { UNIT_TO_M, UNIT_NAMES } from '../maps/vector/common.js';
import { readDxf, looksLikeDxf, looksLikeBinaryDxf, DxfError } from '../maps/vector/dxf.js';
import { readSvg, looksLikeSvg, SvgError } from '../maps/vector/svg.js';
import { dwgToDxf, looksLikeDwg, DwgError } from '../maps/vector/dwg.js';
import { layoutFor, renderVector, toPx } from '../maps/vector/render.js';

// Files live outside any static mount; the only read path is the authenticated route below.
const UPLOAD_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../uploads/backdrops');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const HARD_LIMIT_MB = 50;
const MAX_SIDE = 10000;
const MIN_SIDE = 50;
const MAX_PIXELS = 50_000_000;
const MAX_PER_BRANCH = 20;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: HARD_LIMIT_MB * 1024 * 1024, files: 1 },
});

export const backdropsRouter = Router({ mergeParams: true });

async function branchInScope(req) {
  const id = Number(req.params.branchId);
  const branch = await branches.findById(id);
  if (!branch) throw new AppError(404, 'Branch not found.');
  assertBranchInScope(await resolveScope(req.user), id);
  return branch;
}

function filePathFor(key, mime) {
  return path.join(UPLOAD_DIR, `${key}.${mime === 'image/png' ? 'png' : 'jpg'}`);
}

// Vector plans (Round 16) also keep the original drawing and its parsed lines.
const sourcePathFor = (key, kind) => path.join(UPLOAD_DIR, `${key}.${kind}`);
const vectorPathFor = (key) => path.join(UPLOAD_DIR, `${key}.vector.json`);

function loadVector(key) {
  const file = vectorPathFor(key);
  if (!fs.existsSync(file)) return null;
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** What kind of plan the bytes are, never trusting the file name. */
function sniffKind(buf) {
  if (sniffMime(buf)) return 'image';
  if (looksLikeDwg(buf)) return 'dwg';
  if (looksLikeDxf(buf) || looksLikeBinaryDxf(buf)) return 'dxf';
  if (looksLikeSvg(buf)) return 'svg';
  return null;
}

/** Reads a vector plan into lines and texts, or a 400 with the reason. */
async function readVector(kind, buf) {
  try {
    if (kind === 'svg') return readSvg(buf);
    return readDxf(kind === 'dwg' ? await dwgToDxf(buf) : buf);
  } catch (err) {
    if (err instanceof DxfError || err instanceof SvgError || err instanceof DwgError) throw new AppError(400, err.message);
    throw err;
  }
}

const r4 = (n) => Math.round(n * 1e4) / 1e4;

// Multer errors are plain Errors; turn them into 400s instead of 500s.
function multerGuard(req, res, next) {
  upload.single('file')(req, res, (err) => {
    if (!err) return next();
    if (err.code === 'LIMIT_FILE_SIZE') return next(new AppError(400, `The file is larger than ${HARD_LIMIT_MB} MB.`));
    return next(new AppError(400, 'Upload failed. Send one image file in the "file" field.'));
  });
}

backdropsRouter.get('/', async (req, res, next) => {
  try {
    const branch = await branchInScope(req);
    res.json({ items: await backdrops.listForBranch(branch.id) });
  } catch (err) {
    next(err);
  }
});

backdropsRouter.post('/', requireRole('mall_admin'), multerGuard, async (req, res, next) => {
  try {
    const branch = await branchInScope(req);
    const file = req.file;
    if (!file) throw new AppError(400, 'Choose a plan file.');

    const limitMb = await settings.getNumber('ai_file_size_mb');
    if (file.size > limitMb * 1024 * 1024) throw new AppError(400, `The file is larger than the ${limitMb} MB limit set in Platform settings.`);

    // Pictures (PNG, JPG) are stored as they are; SVG, DXF and DWG drawings are
    // read here and drawn into a PNG (Round 16). Other picture types and PDF
    // pages are turned into PNG in the browser before they get here.
    const kind = sniffKind(file.buffer);
    if (!kind) throw new AppError(400, 'This file type is not accepted. Upload a picture (PNG, JPG, TIFF, WebP, BMP, GIF, HEIC), a PDF, or an SVG, DXF or DWG drawing.');
    if ((await backdrops.countForBranch(branch.id)) >= MAX_PER_BRANCH) {
      throw new AppError(400, `This branch already has ${MAX_PER_BRANCH} uploaded plans. Delete one first.`);
    }

    const key = crypto.randomBytes(16).toString('hex');
    let mime = 'image/png';
    let size;
    let picture = file.buffer;
    let vector = null;
    let layout = null;
    if (kind === 'image') {
      mime = sniffMime(file.buffer);
      try {
        size = imageSize(file.buffer, mime);
      } catch {
        throw new AppError(400, 'The image could not be read.');
      }
      if (size.width < MIN_SIDE || size.height < MIN_SIDE) throw new AppError(400, 'The image is too small to be a floor plan.');
      if (size.width > MAX_SIDE || size.height > MAX_SIDE || size.width * size.height > MAX_PIXELS) {
        throw new AppError(400, `The image is too large (max ${MAX_SIDE} px per side, ${MAX_PIXELS / 1e6} megapixels).`);
      }
    } else {
      vector = await readVector(kind, file.buffer);
      layout = layoutFor(vector);
      picture = renderVector(vector, layout);
      size = { width: layout.width, height: layout.height };
    }

    const target = filePathFor(key, mime);
    fs.writeFileSync(target, picture);
    let mpp = null;
    if (vector) {
      fs.writeFileSync(sourcePathFor(key, kind), file.buffer);
      // Lines and texts in picture pixels, kept for exact walls at reading time.
      const seg = [];
      const s = vector.segments;
      for (let i = 0; i < s.length; i += 5) {
        const [x1, y1] = toPx(layout, s[i], s[i + 1]);
        const [x2, y2] = toPx(layout, s[i + 2], s[i + 3]);
        seg.push(r4(x1), r4(y1), r4(x2), r4(y2), s[i + 4]);
      }
      const texts = vector.texts.map((t) => {
        const [x, y] = toPx(layout, t.x, t.y);
        return { x: r4(x), y: r4(y), text: t.text, layer: t.layer };
      });
      fs.writeFileSync(vectorPathFor(key), JSON.stringify({ kind, k: layout.k, layers: vector.layers, segments: seg, texts }));
      if (vector.unitToM) mpp = vector.unitToM / layout.k;
    }
    const row = await backdrops.insert({
      key,
      branchId: branch.id,
      fileName: path.basename(target),
      originalName: (file.originalname || '').slice(0, 255),
      mimeType: mime,
      sizeBytes: file.size,
      width: size.width,
      height: size.height,
      uploadedBy: req.user.id,
      kind,
      sourceFile: vector ? path.basename(sourcePathFor(key, kind)) : null,
      units: vector?.units ?? null,
      mpp,
    });
    await recordAudit(req, res, {
      action: 'backdrop_uploaded',
      entityType: 'backdrop',
      entityId: key,
      details: { branchId: branch.id, kind, width: size.width, height: size.height, bytes: file.size, ...(vector ? { units: vector.units, lines: vector.segments.length / 5, texts: vector.texts.length } : {}) },
    });
    res.status(201).json({ backdrop: row });
  } catch (err) {
    next(err);
  }
});

backdropsRouter.get('/:key', async (req, res, next) => {
  try {
    const branch = await branchInScope(req);
    const row = await backdrops.find(req.params.key);
    if (!row || row.branchId !== branch.id) throw new AppError(404, 'Plan not found.');
    const file = filePathFor(row.id, row.mimeType);
    if (!fs.existsSync(file)) throw new AppError(404, 'The image file is missing on the server.');
    res.set('Content-Type', row.mimeType);
    res.set('Cache-Control', 'private, max-age=86400');
    fs.createReadStream(file).pipe(res);
  } catch (err) {
    next(err);
  }
});

backdropsRouter.delete('/:key', requireRole('mall_admin'), async (req, res, next) => {
  try {
    const branch = await branchInScope(req);
    const row = await backdrops.find(req.params.key);
    if (!row || row.branchId !== branch.id) throw new AppError(404, 'Plan not found.');
    const map = await maps.findByBranch(branch.id);
    const inUse = (map?.draft?.buildings ?? []).some((b) => (b.levels ?? []).some((l) => l.backdrop?.id === row.id));
    if (inUse) throw new AppError(409, 'This plan is still placed on a level. Remove it from the level first.');
    for (const file of [filePathFor(row.id, row.mimeType), vectorPathFor(row.id), ...(row.kind !== 'image' ? [sourcePathFor(row.id, row.kind)] : [])]) {
      if (fs.existsSync(file)) fs.unlinkSync(file);
    }
    await backdrops.remove(row.id);
    await recordAudit(req, res, { action: 'backdrop_deleted', entityType: 'backdrop', entityId: row.id, details: { branchId: branch.id } });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

// A DXF or DWG that does not say its unit: the mall admin picks it (owner decision
// 2026-10-22), which gives the exact scale. Also corrects a wrong unit in a file.
const unitSchema = z.object({ unit: z.enum(Object.keys(UNIT_TO_M)) });

backdropsRouter.put('/:key/unit', requireRole('mall_admin'), validate(unitSchema), async (req, res, next) => {
  try {
    const branch = await branchInScope(req);
    const row = await backdrops.find(req.params.key);
    if (!row || row.branchId !== branch.id) throw new AppError(404, 'Plan not found.');
    if (row.kind !== 'dxf' && row.kind !== 'dwg') throw new AppError(400, 'Only DXF and DWG drawings have a unit. Calibrate pictures and SVG with two clicks.');
    const vector = loadVector(row.id);
    if (!vector) throw new AppError(404, 'The drawing data is missing on the server. Upload the drawing again.');
    const mpp = UNIT_TO_M[req.body.unit] / vector.k;
    if (mpp < 0.0001 || mpp > 1) throw new AppError(400, `In ${UNIT_NAMES[req.body.unit]} this drawing would be far too small or too large to be a floor plan. Check the unit.`);
    const updated = await backdrops.setUnit(row.id, req.body.unit, mpp);
    await recordAudit(req, res, { action: 'backdrop_unit_set', entityType: 'backdrop', entityId: row.id, details: { branchId: branch.id, from: row.units, to: req.body.unit } });
    res.json({ backdrop: updated });
  } catch (err) {
    next(err);
  }
});

// ---- Read with AI: image → proposal through IQGateway. Never writes to the draft. ----
// Owner decisions 2026-10-22: the AI reads everything (outline, walls, doors,
// named rooms); the old raster "Detect" is gone; only the gateway wallet limits
// how often (no platform cap); every run is audited with its cost.

const convertSchema = z.object({
  levelId: z.string().min(1).max(40),
  crop: z
    .array(z.number().min(0).max(1))
    .length(4)
    .refine(([x0, y0, x1, y1]) => Math.abs(x1 - x0) >= 0.02 && Math.abs(y1 - y0) >= 0.02, 'The box is too small to read.')
    .optional(),
});

/** Path prefix like buildings[0].levels[1] for the target level. */
function levelPath(draft, levelId) {
  for (const [bi, b] of (draft.buildings ?? []).entries()) {
    for (const [li, l] of (b.levels ?? []).entries()) if (l.id === levelId) return `buildings[${bi}].levels[${li}]`;
  }
  return null;
}

/**
 * Checks the proposal inside a copy of the draft and drops every proposed piece
 * the validator names, so a proposal that cannot be saved never reaches the editor.
 */
function keepValid(draft, level, p) {
  const probe = structuredClone(draft);
  for (const b of probe.buildings) {
    for (const l of b.levels) {
      if (l.id !== level.id) continue;
      l.walls = [...(l.walls ?? []), ...p.walls];
      l.openings = [...(l.openings ?? []), ...p.openings];
      l.spaces = [...(l.spaces ?? []), ...p.spaces];
      if (p.outline) l.outline = p.outline;
    }
  }
  const { problems } = validateLayout(probe);
  const at = levelPath(draft, level.id);
  const bad = new Set();
  let badOutline = false;
  for (const prob of problems) {
    if (!prob.startsWith(at + '.')) continue;
    const rest = prob.slice(at.length + 1);
    if (rest.startsWith('outline')) badOutline = true;
    const m = /^(walls|openings|spaces)\[(\d+)\]/.exec(rest);
    if (!m) continue;
    const list = m[1] === 'walls' ? p.walls : m[1] === 'openings' ? p.openings : p.spaces;
    const idx = Number(m[2]) - (level[m[1]] ?? []).length;
    if (idx >= 0 && idx < list.length) bad.add(list[idx].id);
  }
  const walls = p.walls.filter((w) => !bad.has(w.id));
  const openings = p.openings.filter((o) => !bad.has(o.id) && walls.some((w) => w.id === o.wall));
  const spaces = p.spaces.filter((x) => !bad.has(x.id));
  const outline = badOutline ? null : p.outline;
  const kept = new Set([...walls, ...openings, ...spaces].map((x) => x.id));
  const dropped = p.walls.length + p.openings.length + p.spaces.length - kept.size + (p.outline && !outline ? 1 : 0);
  return { walls, openings, spaces, outline, uncertain: p.uncertain.filter((id) => kept.has(id)), dropped };
}

const addCost = (a, b) => ({ credits: a.credits + b.credits, usd: a.usd + b.usd });

backdropsRouter.post('/:key/convert', requireRole('mall_admin'), validate(convertSchema), async (req, res, next) => {
  try {
    const branch = await branchInScope(req);
    const row = await backdrops.find(req.params.key);
    if (!row || row.branchId !== branch.id) throw new AppError(404, 'Plan not found.');

    if (!gateway.aiConfigured()) throw new AppError(503, 'AI reading is not set up. A superadmin must add the IQGateway key on the server.');
    const model = await settings.getText('ai_model');
    if (!model) throw new AppError(409, 'No AI model is chosen yet. A superadmin chooses it in Settings.');
    // Round 19: a mall admin needs credits left; a superadmin reads from the wallet's free part.
    await creditOps.assertCanRead(req.user);

    const map = await maps.findByBranch(branch.id);
    if (!map?.draft) throw new AppError(404, 'This branch has no draft map.');
    let level = null;
    for (const b of map.draft.buildings ?? []) for (const l of b.levels ?? []) if (l.id === req.body.levelId) level = l;
    if (!level) throw new AppError(404, 'Level not found in the draft.');
    if (!level.backdrop || level.backdrop.id !== row.id) {
      throw new AppError(400, 'Place and calibrate this plan on the level, and save, before reading it.');
    }

    const file = filePathFor(row.id, row.mimeType);
    if (!fs.existsSync(file)) throw new AppError(404, 'The image file is missing on the server.');
    const img = decodeImage(fs.readFileSync(file), row.mimeType);

    const crop = req.body.crop ?? null;
    const picture = preparePicture(img, crop);
    const partial = crop != null && picture.box.w * picture.box.h < img.width * img.height * 0.98;
    const storeList = await stores.namesForBranch(branch.id);
    const mpp = level.backdrop.mpp;
    // A vector plan (Round 16): the AI also gets the drawing's layers and texts,
    // and its walls are laid on the drawing's exact lines afterwards.
    const vector = row.kind !== 'image' ? loadVector(row.id) : null;
    // Round 18: is the scale real? Set by hand (calibrated), or a drawing's unit.
    // If not, the AI reads a dimension on the plan and the scale comes from it.
    const scaleKnown = level.backdrop.calibrated === true || (row.mpp != null && Math.abs(row.mpp - mpp) < 1e-7);
    const messages = buildMessages({
      pictureUrl: picture.url,
      widthM: picture.box.w * mpp,
      heightM: picture.box.h * mpp,
      storeNames: storeList.map((x) => x.name),
      partial,
      cad: vector ? cadHints(vector, picture.box) : null,
      scaleKnown,
    });

    // Up to two paid calls: one retry when the answer is not readable JSON.
    let spent = { credits: 0, usd: 0 };
    let usedModel = model;
    let answer = null;
    let truncated = false;
    const record = async (walls, spaces, details, action = 'map_converted') => {
      const cost = { model: usedModel, credits: Math.round(spent.credits * 10000) / 10000, usd: Math.round(spent.usd * 1e6) / 1e6 };
      const conversionId = await backdrops.recordConversion({
        branchId: branch.id,
        key: row.id,
        levelId: level.id,
        usedAi: true,
        wallCount: walls,
        spaceCount: spaces,
        userId: req.user.id,
        model: usedModel,
        credits: cost.credits,
        usd: cost.usd,
        crop: crop ? crop.map((n) => n.toFixed(4)).join(',') : null,
      });
      // Round 19: the paid cost (also of a failed run) comes off the mall admin's credits.
      const balanceAfter = await creditOps.chargeReading(req.user, cost.credits, conversionId);
      await recordAudit(req, res, { action, entityType: 'map', entityId: map.id, details: { branchId: branch.id, levelId: level.id, crop, ...cost, ...details, ...(balanceAfter == null ? {} : { balanceAfter }) } });
      return cost;
    };
    // The answer format the provider accepts; refused formats fall back to the next.
    const formats = responseFormats(model);
    let format = 0;
    const ask = async () => {
      for (;;) {
        try {
          return await gateway.chat({ model, messages, responseFormat: formats[format] });
        } catch (err) {
          if (!err.requestRejected || format >= formats.length - 1) throw err;
          format += 1;
        }
      }
    };
    try {
      for (let attempt = 0; attempt < 2 && !answer; attempt++) {
        const r = await ask();
        spent = addCost(spent, r.cost);
        usedModel = r.model || model;
        if (r.finishReason === 'length') {
          truncated = true;
          break;
        }
        answer = parseAnswer(r.text);
      }
    } catch (err) {
      // A failed second call still leaves the first one paid for: keep the record,
      // and do not tell people that nothing was used.
      if (spent.credits > 0 || spent.usd > 0) {
        await record(0, 0, { failed: err.message }, 'map_convert_failed');
        if (err.requestRejected) throw new AppError(502, 'The chosen AI model could not finish this reading, so nothing was added. Try again in a moment; if it keeps happening, a superadmin can choose another model in Settings.');
      }
      throw err;
    }

    if (!answer) {
      await record(0, 0, { failed: truncated ? 'answer too long' : 'unreadable answer' }, 'map_convert_failed');
      if (truncated) throw new AppError(422, 'This plan has too much detail to read in one go. Drag a box around a part of it and read it section by section.');
      throw new AppError(502, 'The AI answer could not be read. Try again, or read a smaller part of the plan.');
    }
    if (!answer.isFloorPlan) {
      await record(0, 0, { failed: 'not a floor plan' }, 'map_convert_failed');
      throw new AppError(422, `The AI says this is not a floor plan.${answer.notes ? ' ' + answer.notes.slice(0, 300) : ''}`);
    }

    const notes = [];
    // The scale from the dimension the AI read, for a plan whose scale was never set.
    let calib = level.backdrop;
    let scaleFound = null;
    if (!scaleKnown) {
      const found = scaleFromDimension(answer.dimension, picture.box, img);
      if (found) {
        // Keep the plan's centre where it is; only its size changes.
        calib = { ...calib, mpp: found, calibrated: true };
        scaleFound = { mpp: found, mm: Math.round(answer.dimension.mm) };
      } else {
        notes.push('This plan\'s scale was never set and no dimension could be read on it, so sizes may be far off. Set the scale (two clicks on a known length) and read it again.');
      }
    }

    const raw = toProposal(answer, { box: picture.box, image: { width: img.width, height: img.height }, calib, newId, cad: vector });
    // Round 18 (owner decision: measured walls + AI names): the walls are measured
    // from the picture's pixels (drawings already have exact CAD walls), then the
    // rooms are the areas those walls enclose, named from the AI's reading.
    let shaped = raw;
    let measuredWalls = 0;
    if (!vector) {
      const measured = measurePlan(img, calib, { crop });
      if (measured.enough) {
        shaped = mergeMeasured(raw, measured, { newId });
        measuredWalls = shaped.measuredWalls;
      } else {
        notes.push('Few walls could be measured from this picture (it may be a photo or a sketch), so the AI\'s own walls are used. Check them closely.');
      }
    }
    shaped = shapeRooms(shaped, { newId });
    const ok = keepValid(map.draft, level, shaped);
    const storeMatches = matchStores(ok.spaces, storeList);

    if (answer.notes.trim()) notes.push(answer.notes.trim().slice(0, 500));
    if (ok.walls.length === 0 && ok.spaces.length === 0) notes.push('Nothing usable was found. Check the calibration, or box a clearer part of the plan.');
    if (ok.dropped > 0) notes.push(`${ok.dropped} proposed piece${ok.dropped === 1 ? ' was' : 's were'} left out because they could not be saved on this level.`);
    if (ok.uncertain.length > 0) notes.push(`${ok.uncertain.length} piece${ok.uncertain.length === 1 ? ' is' : 's are'} marked uncertain (dashed amber). Check them before adding.`);

    const stats = {
      walls: ok.walls.length,
      doors: ok.openings.length,
      spaces: ok.spaces.length,
      named: ok.spaces.filter((x) => x.name).length,
      uncertain: ok.uncertain.length,
      wallMetres: Math.round(ok.walls.reduce((n, w) => n + Math.hypot(w.b[0] - w.a[0], w.b[1] - w.a[1]), 0)),
      dropped: ok.dropped,
      storeMatches: storeMatches.length,
      // Walls measured from the picture's pixels, and rooms shaped by the walls (Round 18).
      measuredWalls,
      roomsFromWalls: shaped.roomsFromWalls ?? 0,
      // Walls laid on the drawing's exact CAD lines (vector plans only).
      ...(vector ? { exactWalls: ok.walls.length ? Math.min(raw.exactWalls, ok.walls.length) : 0 } : {}),
    };
    const cost = await record(ok.walls.length, ok.spaces.length, { stats });

    res.json({
      proposal: { levelId: level.id, walls: ok.walls, openings: ok.openings, spaces: ok.spaces, outline: ok.outline, uncertain: ok.uncertain, storeMatches, crop },
      // The scale found from a dimension on the plan: the editor applies it to the plan (Round 18).
      scaleFound,
      stats,
      notes,
      usedAi: true,
      cost,
    });
  } catch (err) {
    // A reading that does not succeed always leaves a line in the server log.
    console.warn(`AI reading for branch ${req.params.branchId} by ${req.user?.email}: ${err instanceof AppError ? `${err.httpStatus} ${err.message}` : err?.message}`);
    next(err);
  }
});
