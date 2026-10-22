// Test helpers: start the real app on a random port against the local DB,
// create throw-away records with a unique suffix, and clean them up after.
process.env.RATE_LIMIT = 'off';

import { createApp } from '../src/app.js';
import { runMigrations } from '../src/db/migrate.js';
import { query, sql, getPool } from '../src/db/pool.js';
import * as users from '../src/repos/users.js';
import { hashPassword } from '../src/utils/password.js';

export const PASSWORD = 'TestPass123';

export async function startServer() {
  await runMigrations();
  const app = createApp();
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}/api`;
  return { server, base };
}

export async function stopServer(server) {
  await new Promise((resolve) => server.close(resolve));
  const pool = await getPool();
  await pool.close();
}

export function api(base) {
  return async (method, path, { token, body } = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = text;
    }
    return { status: res.status, body: json };
  };
}

/** Creates a fixture set with a unique tag so tests never collide with real data. */
export async function makeFixtures(tag) {
  const mk = async (role, { mustChange = false, prefix = role } = {}) =>
    users.create({
      email: `${prefix}.${tag}@test.local`,
      fullName: `${prefix} ${tag}`,
      role,
      passwordHash: await hashPassword(PASSWORD),
      mustChange,
    });

  const superadminId = await mk('superadmin');
  const supervisorId = await mk('supervisor');
  const mallAdminId = await mk('mall_admin');
  const ownerId = await mk('store_owner');
  const tempUserId = await mk('supervisor', { mustChange: true, prefix: 'temp' });

  const mallA = (await query(`INSERT INTO malls (name) OUTPUT inserted.id VALUES (@n)`, { n: `Mall A ${tag}` })).recordset[0].id;
  const mallB = (await query(`INSERT INTO malls (name) OUTPUT inserted.id VALUES (@n)`, { n: `Mall B ${tag}` })).recordset[0].id;
  const branchA = (await query(`INSERT INTO branches (mall_id, name) OUTPUT inserted.id VALUES (@m, @n)`, { m: { type: sql.Int, value: mallA }, n: `Branch A ${tag}` })).recordset[0].id;
  const branchB = (await query(`INSERT INTO branches (mall_id, name) OUTPUT inserted.id VALUES (@m, @n)`, { m: { type: sql.Int, value: mallB }, n: `Branch B ${tag}` })).recordset[0].id;

  await query(`INSERT INTO supervisor_assignments (user_id, mall_id) VALUES (@u, @m)`, { u: { type: sql.Int, value: supervisorId }, m: { type: sql.Int, value: mallA } });
  await query(`INSERT INTO mall_admin_assignments (user_id, branch_id) VALUES (@u, @b)`, { u: { type: sql.Int, value: mallAdminId }, b: { type: sql.Int, value: branchA } });
  // The fixture admin reports to the fixture owner (Round 4).
  await query(`UPDATE users SET reports_to = @s WHERE id = @m`, { s: { type: sql.Int, value: supervisorId }, m: { type: sql.Int, value: mallAdminId } });
  const storeA = (await query(`INSERT INTO stores (branch_id, name) OUTPUT inserted.id VALUES (@b, @n)`, { b: { type: sql.Int, value: branchA }, n: `Store A ${tag}` })).recordset[0].id;
  await query(`INSERT INTO store_owner_assignments (user_id, store_id) VALUES (@u, @s)`, { u: { type: sql.Int, value: ownerId }, s: { type: sql.Int, value: storeA } });

  return { superadminId, supervisorId, mallAdminId, ownerId, tempUserId, mallA, mallB, branchA, branchB, storeA };
}

export async function cleanFixtures(tag) {
  const like = `%${tag}%`;
  await query(`DELETE ab FROM announcement_branches ab JOIN announcements a ON a.id = ab.announcement_id JOIN users u ON u.id = a.created_by WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE a FROM announcements a JOIN users u ON u.id = a.created_by WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE pr FROM profile_requests pr JOIN users u ON u.id = pr.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE soa FROM store_owner_assignments soa JOIN users u ON u.id = soa.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE ss FROM store_spaces ss JOIN stores s ON s.id = ss.store_id WHERE s.name LIKE @l`, { l: like });
  // Maps hang off branches: versions first (the pointer on maps blocks the delete), then maps.
  await query(`UPDATE mp SET published_version_id = NULL FROM maps mp JOIN branches b ON b.id = mp.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE v FROM map_versions v JOIN maps mp ON mp.id = v.map_id JOIN branches b ON b.id = mp.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE mc FROM map_conversions mc JOIN branches b ON b.id = mc.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE bd FROM map_backdrops bd JOIN branches b ON b.id = bd.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE mp FROM maps mp JOIN branches b ON b.id = mp.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE FROM stores WHERE name LIKE @l`, { l: like });
  await query(`DELETE FROM branch_options WHERE name LIKE @l`, { l: like });
  await query(`DELETE ma FROM mall_admin_assignments ma JOIN users u ON u.id = ma.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE sa FROM supervisor_assignments sa JOIN users u ON u.id = sa.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE FROM branches WHERE name LIKE @l`, { l: like });
  await query(`DELETE FROM malls WHERE name LIKE @l`, { l: like });
  await query(`DELETE FROM audit_log WHERE actor_email LIKE @l`, { l: like });
  await query(`UPDATE users SET reports_to = NULL WHERE reports_to IN (SELECT id FROM users WHERE email LIKE @l)`, { l: like });
  await query(`DELETE FROM users WHERE email LIKE @l`, { l: like });
}
