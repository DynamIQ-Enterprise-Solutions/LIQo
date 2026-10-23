// Plan pictures (backdrops) and AI readings on Firestore (P1-06A). The files
// themselves stay on disk (src/storage/files.js); only their details live here.
import { col, docOf, runTx, nextId, one, all, Timestamp } from '../../db/firestore.js';
import { fkError } from './util.js';

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
    kind: r.source_kind ?? 'image',
    sourceFile: r.source_file ?? null,
    units: r.units ?? null,
    mpp: r.mpp_from_units == null ? null : Number(r.mpp_from_units),
    needsUnit: (r.source_kind === 'dxf' || r.source_kind === 'dwg') && r.units == null,
  };
}

export async function insert({ key, branchId, fileName, originalName, mimeType, sizeBytes, width, height, uploadedBy, kind = 'image', sourceFile = null, units = null, mpp = null }) {
  await runTx(async (tx) => {
    if (!(await tx.get(docOf('branches', branchId))).exists) throw fkError();
    tx.create(docOf('map_backdrops', key), {
      backdrop_key: key,
      branch_id: Number(branchId),
      file_name: fileName,
      original_name: originalName ?? null,
      mime_type: mimeType,
      size_bytes: sizeBytes,
      width_px: width,
      height_px: height,
      uploaded_by: uploadedBy,
      source_kind: kind,
      source_file: sourceFile,
      units,
      mpp_from_units: mpp,
      uploaded_at: Timestamp.now(),
    });
  });
  return find(key);
}

/** Sets the unit of a vector plan and the exact scale that follows from it. */
export async function setUnit(key, units, mpp) {
  await docOf('map_backdrops', key).update({ units, mpp_from_units: mpp });
  return find(key);
}

export async function find(key) {
  const r = await one('map_backdrops', key);
  return r ? toPublic(r) : null;
}

export async function listForBranch(branchId) {
  const rows = await all(col('map_backdrops').where('branch_id', '==', Number(branchId)));
  return rows.sort((a, b) => b.uploaded_at - a.uploaded_at).map(toPublic);
}

export async function countForBranch(branchId) {
  const snap = await col('map_backdrops').where('branch_id', '==', Number(branchId)).count().get();
  return snap.data().count;
}

export async function remove(key) {
  await docOf('map_backdrops', key).delete();
}

/** One AI reading, with the model and what it cost (Round 15). Also written for failed paid runs. Returns its id. */
export async function recordConversion({ branchId, key, levelId, usedAi, wallCount, spaceCount, userId, model = null, credits = null, usd = null, crop = null }) {
  return runTx(async (tx) => {
    const id = await nextId('map_conversions', tx);
    tx.set(docOf('map_conversions', id), {
      id,
      branch_id: Number(branchId),
      backdrop_key: key,
      level_id: levelId,
      used_ai: !!usedAi,
      wall_count: wallCount,
      space_count: spaceCount,
      requested_by: userId,
      model,
      credits,
      usd,
      crop,
      requested_at: Timestamp.now(),
    });
    return id;
  });
}
