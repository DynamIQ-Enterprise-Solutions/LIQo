import { query, sql } from '../db/pool.js';

function toPublic(r) {
  return {
    id: r.backdrop_key,
    branchId: r.branch_id,
    fileName: r.file_name,
    originalName: r.original_name,
    mimeType: r.mime_type,
    sizeBytes: r.size_bytes,
    width: r.width_px,
    height: r.height_px,
    uploadedBy: r.uploaded_by,
    uploadedAt: r.uploaded_at,
    // Round 16: what was uploaded (image, svg, dxf, dwg); vector plans keep the original.
    kind: r.source_kind ?? 'image',
    sourceFile: r.source_file ?? null,
    units: r.units ?? null,
    // Exact metres per picture pixel, from the drawing's unit (null = calibrate by hand).
    mpp: r.mpp_from_units == null ? null : Number(r.mpp_from_units),
    needsUnit: (r.source_kind === 'dxf' || r.source_kind === 'dwg') && r.units == null,
  };
}

export async function insert({ key, branchId, fileName, originalName, mimeType, sizeBytes, width, height, uploadedBy, kind = 'image', sourceFile = null, units = null, mpp = null }) {
  await query(
    `INSERT INTO map_backdrops (backdrop_key, branch_id, file_name, original_name, mime_type, size_bytes, width_px, height_px, uploaded_by, source_kind, source_file, units, mpp_from_units)
     VALUES (@k, @b, @f, @o, @m, @s, @w, @h, @u, @kind, @src, @units, @mpp)`,
    {
      k: key,
      b: { type: sql.Int, value: branchId },
      f: fileName,
      o: originalName ?? null,
      m: mimeType,
      s: { type: sql.Int, value: sizeBytes },
      w: { type: sql.Int, value: width },
      h: { type: sql.Int, value: height },
      u: { type: sql.Int, value: uploadedBy },
      kind,
      src: sourceFile,
      units,
      mpp: { type: sql.Decimal(18, 10), value: mpp },
    },
  );
  return find(key);
}

/** Sets the unit of a vector plan and the exact scale that follows from it. */
export async function setUnit(key, units, mpp) {
  await query('UPDATE map_backdrops SET units = @units, mpp_from_units = @mpp WHERE backdrop_key = @k', {
    k: key,
    units,
    mpp: { type: sql.Decimal(18, 10), value: mpp },
  });
  return find(key);
}

export async function find(key) {
  const r = await query('SELECT * FROM map_backdrops WHERE backdrop_key = @k', { k: key });
  return r.recordset[0] ? toPublic(r.recordset[0]) : null;
}

export async function listForBranch(branchId) {
  const r = await query('SELECT * FROM map_backdrops WHERE branch_id = @b ORDER BY uploaded_at DESC', { b: { type: sql.Int, value: branchId } });
  return r.recordset.map(toPublic);
}

export async function countForBranch(branchId) {
  const r = await query('SELECT COUNT(*) AS n FROM map_backdrops WHERE branch_id = @b', { b: { type: sql.Int, value: branchId } });
  return r.recordset[0].n;
}

export async function remove(key) {
  await query('DELETE FROM map_backdrops WHERE backdrop_key = @k', { k: key });
}

/** One AI reading, with the model and what it cost (Round 15). Also written for failed paid runs. Returns its id. */
export async function recordConversion({ branchId, key, levelId, usedAi, wallCount, spaceCount, userId, model = null, credits = null, usd = null, crop = null }) {
  const r = await query(
    `INSERT INTO map_conversions (branch_id, backdrop_key, level_id, used_ai, wall_count, space_count, requested_by, model, credits, usd, crop)
     OUTPUT inserted.id VALUES (@b, @k, @l, @ai, @w, @s, @u, @m, @c, @d, @cr)`,
    {
      b: { type: sql.Int, value: branchId },
      k: key,
      l: levelId,
      ai: { type: sql.Bit, value: usedAi },
      w: { type: sql.Int, value: wallCount },
      s: { type: sql.Int, value: spaceCount },
      u: { type: sql.Int, value: userId },
      m: model,
      c: { type: sql.Decimal(18, 4), value: credits },
      d: { type: sql.Decimal(18, 6), value: usd },
      cr: crop,
    },
  );
  return r.recordset[0].id;
}
