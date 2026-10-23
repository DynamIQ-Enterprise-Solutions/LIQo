import { query, sql, withTransaction, txQuery } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';
import { parseHours, hoursText } from '../../utils/hours.js';

const COLS = `s.id, s.branch_id, b.name AS branch_name, m.name AS mall_name, s.name, s.category_id, c.name AS category_name,
  s.logo_url, s.description, s.opening_hours, s.hours_json, s.status, s.contact_phone, s.contact_email, s.is_active, s.created_at, s.updated_at,
  (SELECT COUNT(*) FROM store_spaces ss WHERE ss.store_id = s.id) AS space_count,
  (SELECT COUNT(*) FROM store_owner_assignments soa WHERE soa.store_id = s.id) AS owner_count`;
const FROM = `FROM stores s
  JOIN branches b ON b.id = s.branch_id
  JOIN malls m ON m.id = b.mall_id
  LEFT JOIN branch_options c ON c.id = s.category_id`;

export function toPublic(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    branchName: row.branch_name,
    mallName: row.mall_name,
    name: row.name,
    categoryId: row.category_id,
    categoryName: row.category_name,
    logoUrl: row.logo_url,
    description: row.description,
    openingHours: row.opening_hours,
    hours: parseHours(row.hours_json),
    status: row.status ?? 'open',
    contactPhone: row.contact_phone,
    contactEmail: row.contact_email,
    isActive: !!row.is_active,
    spaceCount: row.space_count,
    ownerCount: row.owner_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function list({ search, status, branchId, offset, pageSize, sortColumn, sortOrder, scopeBranchIds, onlyStoreIds }) {
  const where = [];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (search) {
    where.push('(s.name LIKE @search OR b.name LIKE @search OR c.name LIKE @search)');
    params.search = `%${search}%`;
  }
  if (status === 'active') where.push('s.is_active = 1');
  if (status === 'inactive') where.push('s.is_active = 0');
  if (branchId) {
    where.push('s.branch_id = @branchId');
    params.branchId = { type: sql.Int, value: branchId };
  }
  if (scopeBranchIds) {
    const { clause, params: p } = inList('s.branch_id', scopeBranchIds, 'sb');
    where.push(clause);
    Object.assign(params, p);
  }
  if (onlyStoreIds) {
    const { clause, params: p } = inList('s.id', onlyStoreIds, 'os');
    where.push(clause);
    Object.assign(params, p);
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
  return { items: rows.map(toPublic), totalCount: total };
}

export async function findById(id) {
  const r = await query(`SELECT ${COLS} ${FROM} WHERE s.id = @id`, { id: { type: sql.Int, value: id } });
  return r.recordset[0] ? toPublic(r.recordset[0]) : null;
}

function fieldParams(f) {
  return {
    name: f.name,
    category: f.categoryId == null ? null : { type: sql.Int, value: f.categoryId },
    logo: f.logoUrl ?? null,
    desc: f.description ?? null,
    hours: f.openingHours ?? null,
    phone: f.contactPhone ?? null,
    email: f.contactEmail ?? null,
  };
}

export async function create(fields, createdBy) {
  const r = await query(
    `INSERT INTO stores (branch_id, name, category_id, logo_url, description, opening_hours, contact_phone, contact_email, created_by)
     OUTPUT inserted.id
     VALUES (@branchId, @name, @category, @logo, @desc, @hours, @phone, @email, @by)`,
    { ...fieldParams(fields), branchId: { type: sql.Int, value: fields.branchId }, by: { type: sql.Int, value: createdBy } },
  );
  return findById(r.recordset[0].id);
}

export async function update(id, fields) {
  await query(
    `UPDATE stores SET name = @name, category_id = @category, logo_url = @logo, description = @desc,
            opening_hours = @hours, contact_phone = @phone, contact_email = @email, updated_at = SYSDATETIME()
      WHERE id = @id`,
    { ...fieldParams(fields), id: { type: sql.Int, value: id } },
  );
  return findById(id);
}

export async function setActive(id, active) {
  await query('UPDATE stores SET is_active = @a, updated_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
    a: { type: sql.Bit, value: active },
  });
  return findById(id);
}

// ---- Store ↔ space links ----

export async function spacesFor(storeId) {
  const r = await query('SELECT space_key FROM store_spaces WHERE store_id = @id ORDER BY space_key', { id: { type: sql.Int, value: storeId } });
  return r.recordset.map((x) => x.space_key);
}

export async function setSpaces(storeId, branchId, keys) {
  await withTransaction(async (tx) => {
    await txQuery(tx, 'DELETE FROM store_spaces WHERE store_id = @id', { id: { type: sql.Int, value: storeId } });
    for (const key of keys) {
      await txQuery(tx, 'INSERT INTO store_spaces (store_id, branch_id, space_key) VALUES (@s, @b, @k)', {
        s: { type: sql.Int, value: storeId },
        b: { type: sql.Int, value: branchId },
        k: key,
      });
    }
  });
  return spacesFor(storeId);
}

/** Active stores of a branch, id and name only (AI name matching). */
export async function namesForBranch(branchId) {
  const r = await query('SELECT id, name FROM stores WHERE branch_id = @b AND is_active = 1 ORDER BY name', { b: { type: sql.Int, value: branchId } });
  return r.recordset.map((x) => ({ id: x.id, name: x.name }));
}

/** All links in a branch: space_key → [{storeId, storeName}] */
export async function spaceLinksForBranch(branchId) {
  const r = await query(
    `SELECT ss.space_key, s.id AS store_id, s.name AS store_name
       FROM store_spaces ss JOIN stores s ON s.id = ss.store_id
      WHERE ss.branch_id = @b ORDER BY ss.space_key, s.name`,
    { b: { type: sql.Int, value: branchId } },
  );
  return r.recordset.map((x) => ({ spaceKey: x.space_key, storeId: x.store_id, storeName: x.store_name }));
}

/** The branch of an active store this store owner is assigned to, or null. */
export async function branchOfOwnedActiveStore(userId, storeId) {
  const r = await query(
    `SELECT s.branch_id FROM store_owner_assignments soa JOIN stores s ON s.id = soa.store_id
      WHERE soa.user_id = @uid AND soa.store_id = @sid AND s.is_active = 1`,
    { uid: { type: sql.Int, value: userId }, sid: { type: sql.Int, value: storeId } },
  );
  return r.recordset[0]?.branch_id ?? null;
}

// ---- Round 21: hours and status (mall admin, or the store owner through the narrow route) ----

export async function setHours(id, hours) {
  await query('UPDATE stores SET hours_json = @h, updated_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
    h: { type: sql.NVarChar(sql.MAX), value: hoursText(hours) },
  });
  return findById(id);
}

export async function setStatus(id, status) {
  await query('UPDATE stores SET status = @s, updated_at = SYSDATETIME() WHERE id = @id', { id: { type: sql.Int, value: id }, s: status });
  return findById(id);
}
