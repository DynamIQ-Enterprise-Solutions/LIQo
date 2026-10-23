import { query, sql } from '../../db/pool.js';
import { inList } from '../../db/sqlHelpers.js';

/** Store owners whose stores sit in the given branches (null = all). Paged. */
export async function list({ search, status, offset, pageSize, sortColumn, sortOrder, scopeBranchIds }) {
  const where = ["u.role = 'store_owner'"];
  const params = { offset: { type: sql.Int, value: offset }, limit: { type: sql.Int, value: pageSize } };
  if (search) {
    where.push('(u.email LIKE @search OR u.full_name LIKE @search)');
    params.search = `%${search}%`;
  }
  if (status === 'active') where.push('u.is_active = 1');
  if (status === 'inactive') where.push('u.is_active = 0');
  if (scopeBranchIds) {
    const { clause, params: p } = inList('s.branch_id', scopeBranchIds, 'sb');
    // Owners of stores in scope, plus owners who currently have no store (so they can be re-assigned).
    where.push(
      `(u.id IN (SELECT soa.user_id FROM store_owner_assignments soa JOIN stores s ON s.id = soa.store_id WHERE ${clause})
        OR NOT EXISTS (SELECT 1 FROM store_owner_assignments x WHERE x.user_id = u.id))`,
    );
    Object.assign(params, p);
  }
  const whereSql = `WHERE ${where.join(' AND ')}`;

  const total = (await query(`SELECT COUNT(*) AS n FROM users u ${whereSql}`, params)).recordset[0].n;
  const rows = (
    await query(
      `SELECT u.id, u.email, u.full_name, u.is_active, u.must_change_password, u.last_login_at, u.created_at
         FROM users u ${whereSql} ORDER BY ${sortColumn} ${sortOrder}
       OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY`,
      params,
    )
  ).recordset;

  const storesByUser = await storesForOwners(rows.map((r) => r.id));
  return {
    items: rows.map((r) => ({
      id: r.id,
      email: r.email,
      fullName: r.full_name,
      role: 'store_owner',
      isActive: !!r.is_active,
      mustChangePassword: !!r.must_change_password,
      lastLoginAt: r.last_login_at,
      createdAt: r.created_at,
      stores: storesByUser.get(r.id) || [],
    })),
    totalCount: total,
  };
}

export async function storesForOwners(userIds) {
  const map = new Map();
  if (userIds.length === 0) return map;
  const { clause, params } = inList('soa.user_id', userIds, 'u');
  const r = await query(
    `SELECT soa.user_id, s.id, s.name, s.branch_id, b.name AS branch_name, s.is_active
       FROM store_owner_assignments soa JOIN stores s ON s.id = soa.store_id JOIN branches b ON b.id = s.branch_id
      WHERE ${clause} ORDER BY b.name, s.name`,
    params,
  );
  for (const row of r.recordset) {
    if (!map.has(row.user_id)) map.set(row.user_id, []);
    map.get(row.user_id).push({ id: row.id, name: row.name, branchId: row.branch_id, branchName: row.branch_name, isActive: !!row.is_active });
  }
  return map;
}

export async function storesForOwner(userId) {
  return (await storesForOwners([userId])).get(userId) || [];
}

export async function assign(userId, storeId, assignedBy) {
  await query(
    `IF NOT EXISTS (SELECT 1 FROM store_owner_assignments WHERE user_id = @u AND store_id = @s)
       INSERT INTO store_owner_assignments (user_id, store_id, assigned_by) VALUES (@u, @s, @by)`,
    { u: { type: sql.Int, value: userId }, s: { type: sql.Int, value: storeId }, by: { type: sql.Int, value: assignedBy } },
  );
}

export async function unassign(userId, storeId) {
  await query('DELETE FROM store_owner_assignments WHERE user_id = @u AND store_id = @s', {
    u: { type: sql.Int, value: userId },
    s: { type: sql.Int, value: storeId },
  });
}

export async function ownersForStore(storeId) {
  const r = await query(
    `SELECT u.id, u.email, u.full_name, u.is_active FROM store_owner_assignments soa JOIN users u ON u.id = soa.user_id
      WHERE soa.store_id = @s ORDER BY u.full_name`,
    { s: { type: sql.Int, value: storeId } },
  );
  return r.recordset.map((x) => ({ id: x.id, email: x.email, fullName: x.full_name, isActive: !!x.is_active }));
}
