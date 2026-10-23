import { query, sql } from '../../db/pool.js';

import { KINDS } from '../shared/options.js';

export { KINDS };

function toPublic(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    kind: row.kind,
    name: row.name,
    sortOrder: row.sort_order,
    isActive: !!row.is_active,
    inUse: row.in_use ?? 0,
  };
}

const COLS = `o.id, o.branch_id, o.kind, o.name, o.sort_order, o.is_active,
  (SELECT COUNT(*) FROM stores s WHERE s.category_id = o.id) AS in_use`;

export async function list({ branchId, kind, includeInactive }) {
  const where = ['o.branch_id = @b'];
  const params = { b: { type: sql.Int, value: branchId } };
  if (kind) {
    where.push('o.kind = @k');
    params.k = kind;
  }
  if (!includeInactive) where.push('o.is_active = 1');
  const r = await query(`SELECT ${COLS} FROM branch_options o WHERE ${where.join(' AND ')} ORDER BY o.kind, o.sort_order, o.name`, params);
  return r.recordset.map(toPublic);
}

export async function findById(id) {
  const r = await query(`SELECT ${COLS} FROM branch_options o WHERE o.id = @id`, { id: { type: sql.Int, value: id } });
  return r.recordset[0] ? toPublic(r.recordset[0]) : null;
}

export async function create({ branchId, kind, name, sortOrder = 0 }) {
  const r = await query(
    'INSERT INTO branch_options (branch_id, kind, name, sort_order) OUTPUT inserted.id VALUES (@b, @k, @n, @s)',
    { b: { type: sql.Int, value: branchId }, k: kind, n: name, s: { type: sql.Int, value: sortOrder } },
  );
  return findById(r.recordset[0].id);
}

export async function update(id, { name, sortOrder }) {
  await query('UPDATE branch_options SET name = @n, sort_order = @s, updated_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
    n: name,
    s: { type: sql.Int, value: sortOrder ?? 0 },
  });
  return findById(id);
}

export async function setActive(id, active) {
  await query('UPDATE branch_options SET is_active = @a, updated_at = SYSDATETIME() WHERE id = @id', {
    id: { type: sql.Int, value: id },
    a: { type: sql.Bit, value: active },
  });
  return findById(id);
}

export async function remove(id) {
  await query('DELETE FROM branch_options WHERE id = @id', { id: { type: sql.Int, value: id } });
}
