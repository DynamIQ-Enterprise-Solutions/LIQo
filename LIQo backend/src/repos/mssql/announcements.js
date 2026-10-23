import { query, sql, withTransaction, txQuery } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';
import { toDateOnly, fromDateOnly, todayDateOnly } from '../../utils/dates.js';

const COLS = `a.id, a.title, a.body, a.image_url, a.image_key, a.image_mime, a.starts_on, a.ends_on, a.status, a.store_id, s.name AS store_name,
  a.created_by, u.full_name AS created_by_name, a.created_role, a.reviewed_by, r.full_name AS reviewed_by_name,
  a.reviewed_at, a.reject_reason, a.created_at, a.updated_at`;
const FROM = `FROM announcements a
  JOIN users u ON u.id = a.created_by
  LEFT JOIN users r ON r.id = a.reviewed_by
  LEFT JOIN stores s ON s.id = a.store_id`;

function liveState(row, today) {
  if (row.status !== 'approved') return row.status;
  const start = toDateOnly(row.starts_on);
  const end = toDateOnly(row.ends_on);
  if (today < start) return 'scheduled';
  if (today > end) return 'expired';
  return 'live';
}

export function toPublic(row, branches = []) {
  const today = todayDateOnly();
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    imageUrl: row.image_url,
    // Round 21: one uploaded picture (replaces the link; old links show until the announcement is edited).
    imageKey: row.image_key ?? null,
    imageMime: row.image_mime ?? null,
    startsOn: toDateOnly(row.starts_on),
    endsOn: toDateOnly(row.ends_on),
    status: row.status,
    liveState: liveState(row, today),
    storeId: row.store_id,
    storeName: row.store_name,
    createdBy: row.created_by,
    createdByName: row.created_by_name,
    createdRole: row.created_role,
    reviewedBy: row.reviewed_by,
    reviewedByName: row.reviewed_by_name,
    reviewedAt: row.reviewed_at,
    rejectReason: row.reject_reason,
    branches,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function branchesFor(ids) {
  if (ids.length === 0) return new Map();
  const { clause, params } = inList('ab.announcement_id', ids, 'a');
  const r = await query(
    `SELECT ab.announcement_id, b.id, b.name, m.name AS mall_name
       FROM announcement_branches ab JOIN branches b ON b.id = ab.branch_id JOIN malls m ON m.id = b.mall_id
      WHERE ${clause} ORDER BY m.name, b.name`,
    params,
  );
  const map = new Map();
  for (const row of r.recordset) {
    if (!map.has(row.announcement_id)) map.set(row.announcement_id, []);
    map.get(row.announcement_id).push({ id: row.id, name: row.name, mallName: row.mall_name });
  }
  return map;
}

/**
 * visibility: { all } | { branchIds, includePendingReview } | { ownerId, storeIds }
 */
export async function list({ search, status, live, offset, pageSize, sortColumn, sortOrder, visibility }) {
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };

  if (!visibility.all) {
    if (visibility.ownerId != null) {
      // Store owner: own submissions + approved items for the branches of their stores.
      const sub = inList('ab2.branch_id', visibility.branchIds, 'ob');
      where.push(
        `(a.created_by = @ownerId OR (a.status = 'approved' AND EXISTS (SELECT 1 FROM announcement_branches ab2 WHERE ab2.announcement_id = a.id AND ${sub.clause})))`,
      );
      params.ownerId = { type: sql.Int, value: visibility.ownerId };
      Object.assign(params, sub.params);
    } else {
      const sub = inList('ab2.branch_id', visibility.branchIds, 'sb');
      where.push(`EXISTS (SELECT 1 FROM announcement_branches ab2 WHERE ab2.announcement_id = a.id AND ${sub.clause})`);
      Object.assign(params, sub.params);
    }
  }
  if (search) {
    where.push('(a.title LIKE @search OR a.body LIKE @search OR u.full_name LIKE @search OR s.name LIKE @search)');
    params.search = `%${search}%`;
  }
  if (status) {
    where.push('a.status = @status');
    params.status = status;
  }
  if (live === 'live') {
    where.push("a.status = 'approved' AND a.starts_on <= @today AND a.ends_on >= @today");
    params.today = { type: sql.Date, value: fromDateOnly(todayDateOnly()) };
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = (await query(`SELECT COUNT(*) AS n ${FROM} ${whereSql}`, params)).recordset[0].n;
  const rows = (
    await query(
      `SELECT ${COLS} ${FROM} ${whereSql} ORDER BY ${sortColumn} ${sortOrder}
       OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
      params,
    )
  ).recordset;
  const branches = await branchesFor(rows.map((r) => r.id));
  return { items: rows.map((r) => toPublic(r, branches.get(r.id) || [])), totalCount: total };
}

export async function findById(id) {
  const r = await query(`SELECT ${COLS} ${FROM} WHERE a.id = @id`, { id: { type: sql.Int, value: id } });
  if (!r.recordset[0]) return null;
  const branches = await branchesFor([id]);
  return toPublic(r.recordset[0], branches.get(id) || []);
}

export async function create({ title, body, imageUrl, startsOn, endsOn, status, storeId, createdBy, createdRole, branchIds }) {
  const id = await withTransaction(async (tx) => {
    const r = await txQuery(
      tx,
      `INSERT INTO announcements (title, body, image_url, starts_on, ends_on, status, store_id, created_by, created_role)
       OUTPUT inserted.id
       VALUES (@title, @body, @image, @start, @end, @status, @store, @by, @role)`,
      {
        title,
        body,
        image: imageUrl ?? null,
        start: { type: sql.Date, value: fromDateOnly(startsOn) },
        end: { type: sql.Date, value: fromDateOnly(endsOn) },
        status,
        store: storeId == null ? null : { type: sql.Int, value: storeId },
        by: { type: sql.Int, value: createdBy },
        role: createdRole,
      },
    );
    const newId = r.recordset[0].id;
    for (const b of branchIds) {
      await txQuery(tx, 'INSERT INTO announcement_branches (announcement_id, branch_id) VALUES (@a, @b)', {
        a: { type: sql.Int, value: newId },
        b: { type: sql.Int, value: b },
      });
    }
    return newId;
  });
  return findById(id);
}

export async function update(id, { title, body, imageUrl, startsOn, endsOn, branchIds, status }) {
  await withTransaction(async (tx) => {
    await txQuery(
      tx,
      `UPDATE announcements SET title = @title, body = @body, image_url = @image, starts_on = @start, ends_on = @end,
              status = COALESCE(@status, status), updated_at = SYSDATETIME() WHERE id = @id`,
      {
        id: { type: sql.Int, value: id },
        title,
        body,
        image: imageUrl ?? null,
        start: { type: sql.Date, value: fromDateOnly(startsOn) },
        end: { type: sql.Date, value: fromDateOnly(endsOn) },
        status: status ?? null,
      },
    );
    if (branchIds) {
      await txQuery(tx, 'DELETE FROM announcement_branches WHERE announcement_id = @id', { id: { type: sql.Int, value: id } });
      for (const b of branchIds) {
        await txQuery(tx, 'INSERT INTO announcement_branches (announcement_id, branch_id) VALUES (@a, @b)', {
          a: { type: sql.Int, value: id },
          b: { type: sql.Int, value: b },
        });
      }
    }
  });
  return findById(id);
}

export async function review(id, { status, reviewedBy, reason }) {
  await query(
    `UPDATE announcements SET status = @status, reviewed_by = @by, reviewed_at = SYSDATETIME(),
            reject_reason = @reason, updated_at = SYSDATETIME() WHERE id = @id`,
    { id: { type: sql.Int, value: id }, status, by: { type: sql.Int, value: reviewedBy }, reason: reason ?? null },
  );
  return findById(id);
}

/** Takes some branches off an announcement's targets (it stays for the others). */
export async function removeBranches(id, branchIds) {
  if (!branchIds.length) return findById(id);
  const { clause, params } = inList('branch_id', branchIds, 'r');
  await query(`DELETE FROM announcement_branches WHERE announcement_id = @id AND ${clause}`, { id: { type: sql.Int, value: id }, ...params });
  await query('UPDATE announcements SET updated_at = SYSDATETIME() WHERE id = @id', { id: { type: sql.Int, value: id } });
  return findById(id);
}

export async function remove(id) {
  await query('DELETE FROM announcements WHERE id = @id', { id: { type: sql.Int, value: id } });
}

/** Round 21: sets or clears (null) the announcement's uploaded picture. */
export async function setImage(id, key, mime) {
  await query('UPDATE announcements SET image_key = @k, image_mime = @m, updated_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
    k: key ?? null,
    m: mime ?? null,
  });
  return findById(id);
}
