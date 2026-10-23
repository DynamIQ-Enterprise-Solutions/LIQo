import { query, sql } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';

const COLS = 'm.id, m.name, m.logo_url, m.is_active, m.created_at, m.updated_at';

export function toPublic(row) {
  return {
    id: row.id,
    name: row.name,
    logoUrl: row.logo_url,
    isActive: !!row.is_active,
    branchCount: row.branch_count ?? undefined,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** Branch count of a mall; for a scoped viewer only the branches they can see (A9). */
function branchCount(scopeBranchIds, params) {
  if (!scopeBranchIds) return '(SELECT COUNT(*) FROM branches b WHERE b.mall_id = m.id)';
  const { clause, params: p } = inList('b.id', scopeBranchIds, 'bc');
  Object.assign(params, p);
  return `(SELECT COUNT(*) FROM branches b WHERE b.mall_id = m.id AND ${clause})`;
}

export async function list({ search, status, offset, pageSize, sortColumn, sortOrder, scopeMallIds, scopeBranchIds = null }) {
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (search) {
    where.push('m.name LIKE @search');
    params.search = `%${search}%`;
  }
  if (status === 'active') where.push('m.is_active = 1');
  if (status === 'inactive') where.push('m.is_active = 0');
  if (scopeMallIds) {
    const { clause, params: p } = inList('m.id', scopeMallIds, 's');
    where.push(clause);
    Object.assign(params, p);
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

  const total = (await query(`SELECT COUNT(*) AS n FROM malls m ${whereSql}`, params)).recordset[0].n;
  const rows = (
    await query(
      `SELECT ${COLS}, ${branchCount(scopeBranchIds, params)} AS branch_count
         FROM malls m ${whereSql}
        ORDER BY ${sortColumn} ${sortOrder}
       OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
      params,
    )
  ).recordset;
  return { items: rows.map(toPublic), totalCount: total };
}

export async function findById(id, { scopeBranchIds = null } = {}) {
  const params = { id: { type: sql.Int, value: id } };
  const r = await query(
    `SELECT ${COLS}, ${branchCount(scopeBranchIds, params)} AS branch_count
       FROM malls m WHERE m.id = @id`,
    params,
  );
  return r.recordset[0] ? toPublic(r.recordset[0]) : null;
}

export async function create({ name, logoUrl, createdBy }) {
  const r = await query(
    `INSERT INTO malls (name, logo_url, created_by) OUTPUT inserted.id VALUES (@name, @logo, @by)`,
    { name, logo: logoUrl ?? null, by: { type: sql.Int, value: createdBy } },
  );
  return findById(r.recordset[0].id);
}

export async function update(id, { name, logoUrl }) {
  await query(
    `UPDATE malls SET name = @name, logo_url = @logo, updated_at = SYSDATETIME() WHERE id = @id`,
    { id: { type: sql.Int, value: id }, name, logo: logoUrl ?? null },
  );
  return findById(id);
}

export async function setActive(id, active) {
  await query(`UPDATE malls SET is_active = @a, updated_at = SYSDATETIME() WHERE id = @id`, {
    id: { type: sql.Int, value: id },
    a: { type: sql.Bit, value: active },
  });
  return findById(id);
}

/** What a deactivation would hide: active branches and stores, and the mall's admins. */
export async function impact(id) {
  const r = await query(
    `SELECT (SELECT COUNT(*) FROM branches b WHERE b.mall_id = @id AND b.is_active = 1) AS branches,
            (SELECT COUNT(*) FROM stores s JOIN branches b ON b.id = s.branch_id WHERE b.mall_id = @id AND s.is_active = 1) AS stores,
            (SELECT COUNT(DISTINCT ma.user_id) FROM mall_admin_assignments ma JOIN branches b ON b.id = ma.branch_id WHERE b.mall_id = @id) AS mallAdmins`,
    { id: { type: sql.Int, value: id } },
  );
  return r.recordset[0];
}
