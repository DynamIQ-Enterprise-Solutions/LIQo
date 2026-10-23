import { query, sql, withTransaction, txQuery } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';

export const LOCK_MINUTES = 5;

function parse(json) {
  if (!json) return null;
  try {
    return JSON.parse(json);
  } catch {
    return null;
  }
}

export function toPublic(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    draft: parse(row.draft_json),
    draftVersion: row.draft_version,
    publishedVersionId: row.published_version_id,
    publishedVersion: row.published_version ?? null,
    publishedAt: row.published_at ?? null,
    lock: row.lock_user_id && row.lock_expires_at && new Date(row.lock_expires_at) > new Date()
      ? { userId: row.lock_user_id, userName: row.lock_user_name ?? null, expiresAt: row.lock_expires_at }
      : null,
    updatedAt: row.updated_at,
    updatedBy: row.updated_by,
  };
}

const COLS = `m.id, m.branch_id, m.draft_json, m.draft_version, m.published_version_id, m.lock_user_id, m.lock_expires_at,
  m.updated_at, m.updated_by, v.version AS published_version, v.published_at, u.full_name AS lock_user_name`;
const FROM = `FROM maps m LEFT JOIN map_versions v ON v.id = m.published_version_id LEFT JOIN users u ON u.id = m.lock_user_id`;

export async function findByBranch(branchId) {
  const r = await query(`SELECT ${COLS} ${FROM} WHERE m.branch_id = @b`, { b: { type: sql.Int, value: branchId } });
  return r.recordset[0] ? toPublic(r.recordset[0]) : null;
}

/** One row per branch in scope with its map status. */
export async function statusForBranches(branchIds) {
  const where = branchIds ? inList('b.id', branchIds, 's') : { clause: '1=1', params: {} };
  const r = await query(
    `SELECT b.id AS branch_id, b.name AS branch_name, ml.name AS mall_name, b.is_active,
            m.id AS map_id, m.draft_version, m.lock_user_id, m.lock_expires_at, u.full_name AS lock_user_name,
            v.version AS published_version, v.published_at, v.space_count
       FROM branches b JOIN malls ml ON ml.id = b.mall_id
       LEFT JOIN maps m ON m.branch_id = b.id
       LEFT JOIN map_versions v ON v.id = m.published_version_id
       LEFT JOIN users u ON u.id = m.lock_user_id
      WHERE ${where.clause}
      ORDER BY ml.name, b.name`,
    where.params,
  );
  const now = new Date();
  return r.recordset.map((x) => ({
    branchId: x.branch_id,
    branchName: x.branch_name,
    mallName: x.mall_name,
    branchActive: !!x.is_active,
    hasMap: x.map_id != null,
    draftVersion: x.draft_version ?? 0,
    publishedVersion: x.published_version ?? null,
    publishedAt: x.published_at ?? null,
    spaceCount: x.space_count ?? 0,
    lockedBy: x.lock_user_id && x.lock_expires_at && new Date(x.lock_expires_at) > now ? { userId: x.lock_user_id, userName: x.lock_user_name } : null,
  }));
}

export async function create(branchId, layoutJson, userId) {
  await query(
    `INSERT INTO maps (branch_id, draft_json, draft_version, created_by, updated_by) VALUES (@b, @j, 1, @u, @u)`,
    { b: { type: sql.Int, value: branchId }, j: { type: sql.NVarChar(sql.MAX), value: layoutJson }, u: { type: sql.Int, value: userId } },
  );
  return findByBranch(branchId);
}

/** Conditional update: succeeds only if the stored draft_version equals baseVersion. */
export async function saveDraft(branchId, layoutJson, baseVersion, userId) {
  const r = await query(
    `UPDATE maps SET draft_json = @j, draft_version = draft_version + 1, updated_by = @u, updated_at = SYSDATETIME()
      OUTPUT inserted.draft_version
      WHERE branch_id = @b AND draft_version = @base`,
    {
      b: { type: sql.Int, value: branchId },
      j: { type: sql.NVarChar(sql.MAX), value: layoutJson },
      u: { type: sql.Int, value: userId },
      base: { type: sql.Int, value: baseVersion },
    },
  );
  return r.recordset[0]?.draft_version ?? null;
}

// ---- Lock ----

export async function acquireLock(branchId, userId) {
  const r = await query(
    `UPDATE maps SET lock_user_id = @u, lock_expires_at = DATEADD(minute, ${LOCK_MINUTES}, SYSDATETIME())
      OUTPUT inserted.lock_expires_at
      WHERE branch_id = @b AND (lock_user_id IS NULL OR lock_user_id = @u OR lock_expires_at < SYSDATETIME())`,
    { b: { type: sql.Int, value: branchId }, u: { type: sql.Int, value: userId } },
  );
  return r.recordset[0]?.lock_expires_at ?? null;
}

export async function releaseLock(branchId, userId) {
  await query(`UPDATE maps SET lock_user_id = NULL, lock_expires_at = NULL WHERE branch_id = @b AND lock_user_id = @u`, {
    b: { type: sql.Int, value: branchId },
    u: { type: sql.Int, value: userId },
  });
}

/** Clears the edit lock whoever holds it. Returns how many maps were touched (0 when the branch has none). */
export async function forceReleaseLock(branchId) {
  const r = await query(`UPDATE maps SET lock_user_id = NULL, lock_expires_at = NULL OUTPUT inserted.id WHERE branch_id = @b`, {
    b: { type: sql.Int, value: branchId },
  });
  return r.recordset.length;
}

export async function holdsLock(branchId, userId) {
  const r = await query(`SELECT 1 AS ok FROM maps WHERE branch_id = @b AND lock_user_id = @u AND lock_expires_at > SYSDATETIME()`, {
    b: { type: sql.Int, value: branchId },
    u: { type: sql.Int, value: userId },
  });
  return !!r.recordset[0];
}

// ---- Versions ----

export async function versions(mapId) {
  const r = await query(
    `SELECT v.id, v.version, v.space_count, v.note, v.published_at, v.published_by, u.full_name AS published_by_name
       FROM map_versions v LEFT JOIN users u ON u.id = v.published_by WHERE v.map_id = @m ORDER BY v.version DESC`,
    { m: { type: sql.Int, value: mapId } },
  );
  return r.recordset.map((x) => ({
    id: x.id,
    version: x.version,
    spaceCount: x.space_count,
    note: x.note,
    publishedAt: x.published_at,
    publishedBy: x.published_by,
    publishedByName: x.published_by_name,
  }));
}

export async function versionLayout(mapId, version) {
  const r = await query(`SELECT layout_json, version, published_at FROM map_versions WHERE map_id = @m AND version = @v`, {
    m: { type: sql.Int, value: mapId },
    v: { type: sql.Int, value: version },
  });
  if (!r.recordset[0]) return null;
  return { layout: parse(r.recordset[0].layout_json), version: r.recordset[0].version, publishedAt: r.recordset[0].published_at };
}

export async function publishedLayout(branchId) {
  const r = await query(
    `SELECT v.layout_json, v.version, v.published_at FROM maps m JOIN map_versions v ON v.id = m.published_version_id WHERE m.branch_id = @b`,
    { b: { type: sql.Int, value: branchId } },
  );
  if (!r.recordset[0]) return null;
  return { layout: parse(r.recordset[0].layout_json), version: r.recordset[0].version, publishedAt: r.recordset[0].published_at };
}

/**
 * Writes a new immutable version and switches the pointer in one transaction.
 * Re-checks draft_version inside the transaction so a stale publish is refused.
 */
export async function publish({ branchId, layoutJson, spaceCount, baseVersion, userId, note = null, resetDraftTo = null }) {
  return withTransaction(async (tx) => {
    const row = (
      await txQuery(tx, `SELECT id, draft_version FROM maps WITH (UPDLOCK, HOLDLOCK) WHERE branch_id = @b`, { b: { type: sql.Int, value: branchId } })
    ).recordset[0];
    if (!row) return { error: 'not_found' };
    if (baseVersion != null && row.draft_version !== baseVersion) return { error: 'stale', draftVersion: row.draft_version };

    const next = (await txQuery(tx, `SELECT ISNULL(MAX(version), 0) + 1 AS v FROM map_versions WHERE map_id = @m`, { m: { type: sql.Int, value: row.id } })).recordset[0].v;
    const ins = await txQuery(
      tx,
      `INSERT INTO map_versions (map_id, version, layout_json, space_count, note, published_by) OUTPUT inserted.id
       VALUES (@m, @v, @j, @c, @n, @u)`,
      {
        m: { type: sql.Int, value: row.id },
        v: { type: sql.Int, value: next },
        j: { type: sql.NVarChar(sql.MAX), value: layoutJson },
        c: { type: sql.Int, value: spaceCount },
        n: note,
        u: { type: sql.Int, value: userId },
      },
    );
    const params = {
      b: { type: sql.Int, value: branchId },
      p: { type: sql.Int, value: ins.recordset[0].id },
      u: { type: sql.Int, value: userId },
    };
    let sqlText = `UPDATE maps SET published_version_id = @p, updated_by = @u, updated_at = SYSDATETIME()`;
    if (resetDraftTo != null) {
      sqlText += `, draft_json = @d, draft_version = draft_version + 1`;
      params.d = { type: sql.NVarChar(sql.MAX), value: resetDraftTo };
    }
    sqlText += ` OUTPUT inserted.draft_version WHERE branch_id = @b`;
    const upd = await txQuery(tx, sqlText, params);
    return { version: next, draftVersion: upd.recordset[0].draft_version };
  });
}

export async function remove(branchId) {
  await withTransaction(async (tx) => {
    const row = (await txQuery(tx, `SELECT id FROM maps WHERE branch_id = @b`, { b: { type: sql.Int, value: branchId } })).recordset[0];
    if (!row) return;
    await txQuery(tx, `UPDATE maps SET published_version_id = NULL WHERE id = @m`, { m: { type: sql.Int, value: row.id } });
    await txQuery(tx, `DELETE FROM map_versions WHERE map_id = @m`, { m: { type: sql.Int, value: row.id } });
    await txQuery(tx, `DELETE FROM maps WHERE id = @m`, { m: { type: sql.Int, value: row.id } });
  });
}
