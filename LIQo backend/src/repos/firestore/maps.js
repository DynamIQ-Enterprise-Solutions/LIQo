// Maps on Firestore (P1-06A). The map documents themselves (draft and every
// published version) are JSON files on disk (src/storage/files.js mapFiles):
// Firestore documents are capped at 1 MB. Firestore keeps the details: the
// draft version, the lock and one small record per published version.
//
// One server process writes maps, so a per-branch queue keeps the file write
// and the version bump together (SQL: one UPDATE with a version check).
import { col, docOf, getDb, runTx, nextId, all, one, uniqueRef, Timestamp } from '../../db/firestore.js';
import { mapFiles } from '../../storage/files.js';
import { byId, compare, dupError, fkError } from './util.js';

export const LOCK_MINUTES = 5;

const queues = new Map();
/** Runs [fn] after every earlier map write of this branch has finished. */
function serial(branchId, fn) {
  const key = Number(branchId);
  const run = (queues.get(key) ?? Promise.resolve()).then(fn, fn);
  queues.set(key, run.catch(() => {}));
  return run;
}

const parse = (json) => {
  if (!json) return null;
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
};

async function mapOf(branchId) {
  const snap = await col('maps').where('branch_id', '==', Number(branchId)).limit(1).get();
  return snap.empty ? null : { ref: snap.docs[0].ref, data: snap.docs[0].data() };
}

const toDate = (t) => (t ? t.toDate() : null);
const lockLive = (m, now = new Date()) => !!(m.lock_user_id && m.lock_expires_at && m.lock_expires_at.toDate() > now);

async function shape(m) {
  const live = lockLive(m);
  const lockName = live ? (await one('users', m.lock_user_id))?.full_name ?? null : null;
  return {
    id: m.id,
    branchId: m.branch_id,
    draft: mapFiles.readDraft(m.branch_id),
    draftVersion: m.draft_version,
    publishedVersionId: m.published_version_id ?? null,
    publishedVersion: m.published_version ?? null,
    publishedAt: toDate(m.published_at),
    lock: live ? { userId: m.lock_user_id, userName: lockName, expiresAt: m.lock_expires_at.toDate() } : null,
    updatedAt: toDate(m.updated_at),
    updatedBy: m.updated_by,
  };
}

export async function findByBranch(branchId) {
  const m = await mapOf(branchId);
  return m ? shape(m.data) : null;
}

/** One row per branch in scope with its map status. */
export async function statusForBranches(branchIds) {
  const [branches, malls, maps, users] = await Promise.all([all(col('branches')), all(col('malls')), col('maps').get(), all(col('users'))]);
  const mallById = byId(malls);
  const userById = byId(users);
  const mapByBranch = new Map(maps.docs.map((d) => [d.data().branch_id, d.data()]));
  const wanted = branchIds ? new Set(branchIds.map(Number)) : null;
  const now = new Date();
  return branches
    .filter((b) => !wanted || wanted.has(b.id))
    .map((b) => ({ b, mallName: mallById.get(b.mall_id)?.name ?? null }))
    .sort((x, y) => compare(x.mallName, y.mallName) || compare(x.b.name, y.b.name))
    .map(({ b, mallName }) => {
      const m = mapByBranch.get(b.id);
      return {
        branchId: b.id,
        branchName: b.name,
        mallName,
        branchActive: !!b.is_active,
        hasMap: !!m,
        draftVersion: m?.draft_version ?? 0,
        publishedVersion: m?.published_version ?? null,
        publishedAt: toDate(m?.published_at),
        spaceCount: m?.published_space_count ?? 0,
        lockedBy: m && lockLive(m, now) ? { userId: m.lock_user_id, userName: userById.get(m.lock_user_id)?.full_name ?? null } : null,
      };
    });
}

export async function create(branchId, layoutJson, userId) {
  await serial(branchId, async () => {
    await runTx(async (tx) => {
      if (!(await tx.get(docOf('branches', branchId))).exists) throw fkError();
      const guard = uniqueRef('map_branch', branchId);
      if ((await tx.get(guard)).exists) throw dupError();
      const id = await nextId('maps', tx);
      tx.set(guard, { id });
      tx.set(docOf('maps', id), {
        id,
        branch_id: Number(branchId),
        draft_version: 1,
        latest_version: 0,
        published_version_id: null,
        published_version: null,
        published_at: null,
        published_space_count: 0,
        lock_user_id: null,
        lock_expires_at: null,
        created_by: userId,
        updated_by: userId,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    mapFiles.writeDraft(branchId, parse(layoutJson));
  });
  return findByBranch(branchId);
}

/** Conditional update: succeeds only if the stored draft_version equals baseVersion. */
export function saveDraft(branchId, layoutJson, baseVersion, userId) {
  return serial(branchId, async () => {
    const m = await mapOf(branchId);
    if (!m || m.data.draft_version !== baseVersion) return null;
    mapFiles.writeDraft(branchId, parse(layoutJson));
    const next = baseVersion + 1;
    await m.ref.update({ draft_version: next, updated_by: userId, updated_at: Timestamp.now() });
    return next;
  });
}

// ---- Lock ----

export async function acquireLock(branchId, userId) {
  const m = await mapOf(branchId);
  if (!m) return null;
  return runTx(async (tx) => {
    const cur = (await tx.get(m.ref)).data();
    const free = !cur.lock_user_id || cur.lock_user_id === userId || !cur.lock_expires_at || cur.lock_expires_at.toDate() < new Date();
    if (!free) return null;
    const expires = new Date(Date.now() + LOCK_MINUTES * 60 * 1000);
    tx.update(m.ref, { lock_user_id: userId, lock_expires_at: Timestamp.fromDate(expires) });
    return expires;
  });
}

export async function releaseLock(branchId, userId) {
  const m = await mapOf(branchId);
  if (!m) return;
  await runTx(async (tx) => {
    const cur = (await tx.get(m.ref)).data();
    if (cur.lock_user_id === userId) tx.update(m.ref, { lock_user_id: null, lock_expires_at: null });
  });
}

/** Clears the edit lock whoever holds it. Returns how many maps were touched (0 when the branch has none). */
export async function forceReleaseLock(branchId) {
  const m = await mapOf(branchId);
  if (!m) return 0;
  await m.ref.update({ lock_user_id: null, lock_expires_at: null });
  return 1;
}

export async function holdsLock(branchId, userId) {
  const m = await mapOf(branchId);
  return !!m && m.data.lock_user_id === userId && lockLive(m.data);
}

// ---- Versions ----

export async function versions(mapId) {
  const [rows, users] = await Promise.all([all(col('map_versions').where('map_id', '==', Number(mapId))), all(col('users'))]);
  const u = byId(users);
  return rows
    .sort((a, b) => b.version - a.version)
    .map((x) => ({
      id: x.id,
      version: x.version,
      spaceCount: x.space_count,
      note: x.note,
      publishedAt: x.published_at,
      publishedBy: x.published_by,
      publishedByName: u.get(x.published_by)?.full_name ?? null,
    }));
}

export async function versionLayout(mapId, version) {
  const rows = await all(col('map_versions').where('map_id', '==', Number(mapId)).where('version', '==', Number(version)).limit(1));
  if (!rows[0]) return null;
  const v = rows[0];
  return { layout: mapFiles.readVersion(v.branch_id, v.version), version: v.version, publishedAt: v.published_at };
}

export async function publishedLayout(branchId) {
  const m = await mapOf(branchId);
  if (!m || m.data.published_version == null) return null;
  return { layout: mapFiles.readVersion(branchId, m.data.published_version), version: m.data.published_version, publishedAt: toDate(m.data.published_at) };
}

/**
 * Writes a new immutable version and switches the pointer. A stale publish is
 * refused. The version file is written first; if recording it fails, the file
 * is dropped again so the number is free for the next publish.
 */
export function publish({ branchId, layoutJson, spaceCount, baseVersion, userId, note = null, resetDraftTo = null }) {
  return serial(branchId, async () => {
    const m = await mapOf(branchId);
    if (!m) return { error: 'not_found' };
    if (baseVersion != null && m.data.draft_version !== baseVersion) return { error: 'stale', draftVersion: m.data.draft_version };
    const next = (m.data.latest_version ?? 0) + 1;
    mapFiles.writeVersion(branchId, next, parse(layoutJson));
    let draftVersion;
    try {
      draftVersion = await runTx(async (tx) => {
        const cur = (await tx.get(m.ref)).data();
        if (baseVersion != null && cur.draft_version !== baseVersion) throw Object.assign(new Error('stale'), { stale: cur.draft_version });
        const vid = await nextId('map_versions', tx);
        const now = Timestamp.now();
        tx.set(docOf('map_versions', vid), {
          id: vid,
          map_id: m.data.id,
          branch_id: Number(branchId),
          version: next,
          space_count: spaceCount,
          note,
          published_by: userId,
          published_at: now,
        });
        const dv = resetDraftTo != null ? cur.draft_version + 1 : cur.draft_version;
        tx.update(m.ref, {
          published_version_id: vid,
          published_version: next,
          published_at: now,
          published_space_count: spaceCount,
          latest_version: next,
          draft_version: dv,
          updated_by: userId,
          updated_at: now,
        });
        return dv;
      });
    } catch (e) {
      mapFiles.discardUnrecordedVersion(branchId, next);
      if (e.stale != null) return { error: 'stale', draftVersion: e.stale };
      throw e;
    }
    if (resetDraftTo != null) mapFiles.writeDraft(branchId, parse(resetDraftTo));
    return { version: next, draftVersion };
  });
}

export function remove(branchId) {
  return serial(branchId, async () => {
    const m = await mapOf(branchId);
    if (!m) return;
    const vers = await col('map_versions').where('map_id', '==', m.data.id).get();
    const batch = getDb().batch();
    for (const d of vers.docs) batch.delete(d.ref);
    batch.delete(m.ref);
    batch.delete(uniqueRef('map_branch', branchId));
    await batch.commit();
    mapFiles.removeBranch(branchId);
  });
}
