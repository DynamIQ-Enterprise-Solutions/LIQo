// Driver-neutral test access to the data (P1-06A). The suite runs on SQL Server
// and on the Firestore emulator; tests that set up records or check what was
// written go through these helpers instead of SQL, so both runs share one test.
import { config } from '../../src/config.js';
import * as malls from '../../src/repos/malls.js';
import * as branches from '../../src/repos/branches.js';
import * as stores from '../../src/repos/stores.js';
import * as options from '../../src/repos/options.js';
import * as owners from '../../src/repos/owners.js';
import * as assignments from '../../src/repos/assignments.js';
import * as settings from '../../src/repos/settings.js';

export const FIRESTORE = config.db.driver === 'firestore';

const sqlDb = FIRESTORE ? null : await import('../../src/db/pool.js');
const fsDb = FIRESTORE ? await import('../../src/db/firestore.js') : null;
const files = await import('../../src/storage/files.js');

const int = (v) => ({ type: sqlDb.sql.Int, value: v });
const rowsOf = async (text, params) => (await sqlDb.query(text, params)).recordset;
/** Every document of a Firestore collection (dates as JS Dates). */
const docs = (name) => fsDb.all(fsDb.col(name));

/** Gets the database ready for a test file (SQL Server: migrations). */
export async function prepare() {
  if (!FIRESTORE) {
    const { runMigrations } = await import('../../src/db/migrate.js');
    await runMigrations();
  }
}

/** Closes the connection when a test file ends, so the process can exit. */
export async function close() {
  if (FIRESTORE) await fsDb.getDb().terminate();
  else await (await sqlDb.getPool()).close();
}

// ---- Setting up records ----

export async function insertMall(name) {
  return (await malls.create({ name, logoUrl: null, createdBy: null })).id;
}
export async function insertBranch(mallId, name) {
  return (await branches.create({ mallId, name }, null)).id;
}
export async function insertStore(branchId, name) {
  return (await stores.create({ branchId, name }, null)).id;
}
export async function insertOption(branchId, kind, name) {
  return (await options.create({ branchId, kind, name })).id;
}
export const assignOwnerMall = (userId, mallId) => assignments.replaceSupervisorAssignments(userId, { mallIds: [mallId], branchIds: [] }, null);
export const assignAdminBranch = (userId, branchId) => assignments.replaceMallAdminAssignments(userId, { branchIds: [branchId] }, null);
export const assignStoreOwner = (userId, storeId) => owners.assign(userId, storeId, null);

/** Sets one platform setting (and drops the cached settings). */
export const setSetting = (key, value) => settings.setMany({ [key]: String(value) }, null);

/** Changes stored fields of a user directly: is_active, email, failed_logins, locked_until, reports_to. */
export async function setUser(id, fields) {
  if (FIRESTORE) {
    const patch = { ...fields };
    if (fields.email !== undefined) {
      const cur = (await fsDb.docOf('users', id).get()).data();
      const batch = fsDb.getDb().batch();
      batch.delete(fsDb.uniqueRef('email', cur.email));
      batch.set(fsDb.uniqueRef('email', fields.email), { userId: Number(id) });
      patch.email_lc = String(fields.email).toLowerCase();
      batch.update(fsDb.docOf('users', id), patch);
      await batch.commit();
    } else {
      if (patch.is_active !== undefined) patch.is_active = !!patch.is_active;
      await fsDb.docOf('users', id).update(patch);
    }
    fsDb.invalidate();
    return;
  }
  const sets = [];
  const params = { id: int(id) };
  for (const [k, v] of Object.entries(fields)) {
    sets.push(`${k} = @${k}`);
    params[k] = k === 'email' ? v : k === 'locked_until' ? { type: sqlDb.sql.DateTime2, value: v } : v == null ? null : int(typeof v === 'boolean' ? Number(v) : v);
  }
  await sqlDb.query(`UPDATE users SET ${sets.join(', ')} WHERE id = @id`, params);
}

/** A user's stored row (snake_case), or undefined. */
export async function userRow(id) {
  if (FIRESTORE) return (await fsDb.one('users', id)) ?? undefined;
  return (await rowsOf(`SELECT * FROM users WHERE id = @id`, { id: int(id) }))[0];
}

export async function userIdByEmail(email) {
  if (FIRESTORE) return (await docs('users')).find((u) => u.email.toLowerCase() === email.toLowerCase())?.id;
  return (await rowsOf(`SELECT id FROM users WHERE email = @e`, { e: email }))[0]?.id;
}

// ---- Checking what was written ----

/**
 * Audit rows, oldest first, matching every given filter: actorEmail, action,
 * actions (any of), actionPrefix, entityType, entityId, detailsContains.
 */
export async function auditRows(f = {}) {
  let rows;
  if (FIRESTORE) {
    rows = await docs('audit_log');
  } else {
    rows = await rowsOf(
      `SELECT id, actor_id, actor_email, action, entity_type, entity_id, details, created_at FROM audit_log
        WHERE (@e IS NULL OR actor_email = @e) AND (@a IS NULL OR action = @a) AND (@id IS NULL OR entity_id = @id)`,
      { e: f.actorEmail ?? null, a: f.action ?? null, id: f.entityId == null ? null : String(f.entityId) },
    );
  }
  return rows
    .filter((r) => f.actorEmail == null || String(r.actor_email).toLowerCase() === f.actorEmail.toLowerCase())
    .filter((r) => f.action == null || r.action === f.action)
    .filter((r) => !f.actions || f.actions.includes(r.action))
    .filter((r) => f.actionPrefix == null || String(r.action).startsWith(f.actionPrefix))
    .filter((r) => f.entityType == null || r.entity_type === f.entityType)
    .filter((r) => f.entityId == null || r.entity_id === String(f.entityId))
    .filter((r) => f.detailsContains == null || String(r.details ?? '').includes(f.detailsContains))
    .sort((a, b) => a.id - b.id);
}

/** Ledger rows of a user, oldest first: { kind, delta, conversion_id }. */
export async function ledger(userId) {
  const rows = FIRESTORE
    ? (await docs('ai_credit_ledger')).filter((l) => l.user_id === Number(userId))
    : await rowsOf(`SELECT * FROM ai_credit_ledger WHERE user_id = @u`, { u: int(userId) });
  return rows.sort((a, b) => a.id - b.id).map((l) => ({ ...l, delta: Number(l.delta) }));
}

/** The newest AI reading record of a branch, or undefined. */
export async function latestConversion(branchId) {
  if (FIRESTORE) return (await docs('map_conversions')).filter((c) => c.branch_id === Number(branchId)).sort((a, b) => b.id - a.id)[0];
  return (await rowsOf('SELECT TOP 1 * FROM map_conversions WHERE branch_id = @b ORDER BY id DESC', { b: int(branchId) }))[0];
}

/** A reading record by id, or undefined. */
export async function conversion(id) {
  if (FIRESTORE) return (await fsDb.one('map_conversions', id)) ?? undefined;
  return (await rowsOf('SELECT * FROM map_conversions WHERE id = @id', { id: int(id) }))[0];
}

/** A stored balance row, or undefined. */
export async function balanceRow(userId) {
  if (FIRESTORE) return (await fsDb.one('ai_credit_balances', userId)) ?? undefined;
  return (await rowsOf(`SELECT * FROM ai_credit_balances WHERE user_id = @u`, { u: int(userId) }))[0];
}

// ---- Cleaning up ----

async function deleteAll(refs) {
  for (let i = 0; i < refs.length; i += 400) {
    const batch = fsDb.getDb().batch();
    refs.slice(i, i + 400).forEach((r) => batch.delete(r));
    await batch.commit();
  }
}

/** Removes every record a test file made (all carry its unique tag). */
export async function cleanTagged(tag) {
  if (!FIRESTORE) return cleanTaggedSql(tag);
  const t = tag.toLowerCase();
  const has = (v) => String(v ?? '').toLowerCase().includes(t);
  const snapOf = (name) => fsDb.col(name).get();
  const [users, mallDocs, branchDocs, storeDocs] = await Promise.all([docs('users'), docs('malls'), docs('branches'), docs('stores')]);
  const userIds = new Set(users.filter((u) => has(u.email)).map((u) => u.id));
  const mallIds = new Set(mallDocs.filter((m) => has(m.name)).map((m) => m.id));
  const branchIds = new Set(branchDocs.filter((b) => has(b.name) || mallIds.has(b.mall_id)).map((b) => b.id));
  const storeIds = new Set(storeDocs.filter((s) => has(s.name) || branchIds.has(s.branch_id)).map((s) => s.id));
  const reportIds = new Set();

  const refs = [];
  const pick = async (name, test) => {
    const snap = await snapOf(name);
    for (const d of snap.docs) if (test(d.data(), d.id)) refs.push(d.ref);
    return snap;
  };
  await pick('announcements', (a) => userIds.has(a.created_by));
  await pick('profile_requests', (r) => userIds.has(r.user_id));
  await pick('store_owner_assignments', (l) => userIds.has(l.user_id) || storeIds.has(l.store_id));
  await pick('store_spaces', (s) => storeIds.has(s.store_id));
  await pick('map_versions', (v) => branchIds.has(v.branch_id));
  await pick('maps', (m) => branchIds.has(m.branch_id));
  const conv = await snapOf('map_conversions');
  const convIds = new Set(conv.docs.filter((d) => branchIds.has(d.data().branch_id)).map((d) => d.data().id));
  conv.docs.filter((d) => convIds.has(d.data().id)).forEach((d) => refs.push(d.ref));
  await pick('ai_credit_ledger', (l) => userIds.has(l.user_id) || convIds.has(l.conversion_id));
  await pick('ai_credit_requests', (r) => userIds.has(r.user_id));
  await pick('ai_credit_balances', (b) => userIds.has(b.user_id));
  (await snapOf('problem_reports')).docs.forEach((d) => {
    if (userIds.has(d.data().reporter_id)) {
      reportIds.add(d.data().id);
      refs.push(d.ref);
    }
  });
  await pick('problem_report_messages', (m) => reportIds.has(m.report_id));
  await pick('map_backdrops', (b) => branchIds.has(b.branch_id));
  await pick('connector_outages', (o) => branchIds.has(o.branch_id));
  await pick('shopper_counts', (c) => branchIds.has(c.branch_id));
  await pick('map_packages', (p) => branchIds.has(p.branch_id));
  await pick('stores', (s) => storeIds.has(s.id));
  await pick('branch_options', (o) => has(o.name) || branchIds.has(o.branch_id));
  await pick('mall_admin_assignments', (l) => userIds.has(l.user_id) || branchIds.has(l.branch_id));
  await pick('supervisor_assignments', (l) => userIds.has(l.user_id) || mallIds.has(l.mall_id) || branchIds.has(l.branch_id));
  await pick('branches', (b) => branchIds.has(b.id));
  await pick('malls', (m) => mallIds.has(m.id));
  await pick('audit_log', (a) => has(a.actor_email));
  await pick('users', (u) => userIds.has(u.id));
  const guards = new Set([...userIds].flatMap((id) => [`profile_pending:${id}`, `credit_pending:${id}`]).concat([...branchIds].map((id) => `map_branch:${id}`)));
  await pick('_unique', (_, id) => id.includes(t) || guards.has(id));
  await deleteAll(refs);

  // Nobody reports to a removed person any more.
  const left = (await snapOf('users')).docs.filter((d) => userIds.has(d.data().reports_to));
  for (const d of left) await d.ref.update({ reports_to: null });
  for (const id of branchIds) files.mapFiles.removeBranch(id);
  fsDb.invalidate();
}

async function cleanTaggedSql(tag) {
  const { query } = sqlDb;
  const like = `%${tag}%`;
  // Round 21: shopper package files of the tagged branches.
  for (const { id } of await rowsOf(`SELECT id FROM branches WHERE name LIKE @l`, { l: like })) files.packageFiles.removeBranch(id);
  await query(`DELETE ab FROM announcement_branches ab JOIN announcements a ON a.id = ab.announcement_id JOIN users u ON u.id = a.created_by WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE a FROM announcements a JOIN users u ON u.id = a.created_by WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE pr FROM profile_requests pr JOIN users u ON u.id = pr.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE soa FROM store_owner_assignments soa JOIN users u ON u.id = soa.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE ss FROM store_spaces ss JOIN stores s ON s.id = ss.store_id WHERE s.name LIKE @l`, { l: like });
  // Maps hang off branches: versions first (the pointer on maps blocks the delete), then maps.
  await query(`UPDATE mp SET published_version_id = NULL FROM maps mp JOIN branches b ON b.id = mp.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE v FROM map_versions v JOIN maps mp ON mp.id = v.map_id JOIN branches b ON b.id = mp.branch_id WHERE b.name LIKE @l`, { l: like });
  // Round 19: AI credits and problem reports hang off users (and the ledger off readings).
  await query(`DELETE l FROM ai_credit_ledger l JOIN users u ON u.id = l.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE l FROM ai_credit_ledger l JOIN map_conversions mc ON mc.id = l.conversion_id JOIN branches b ON b.id = mc.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE r FROM ai_credit_requests r JOIN users u ON u.id = r.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE cb FROM ai_credit_balances cb JOIN users u ON u.id = cb.user_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE m FROM problem_report_messages m JOIN problem_reports r ON r.id = m.report_id JOIN users u ON u.id = r.reporter_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE r FROM problem_reports r JOIN users u ON u.id = r.reporter_id WHERE u.email LIKE @l`, { l: like });
  await query(`DELETE mc FROM map_conversions mc JOIN branches b ON b.id = mc.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE bd FROM map_backdrops bd JOIN branches b ON b.id = bd.branch_id WHERE b.name LIKE @l`, { l: like });
  // Round 21: out-of-service marks and shopper counts hang off branches.
  await query(`DELETE o FROM connector_outages o JOIN branches b ON b.id = o.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE c FROM shopper_counts c JOIN branches b ON b.id = c.branch_id WHERE b.name LIKE @l`, { l: like });
  await query(`DELETE p FROM map_packages p JOIN branches b ON b.id = p.branch_id WHERE b.name LIKE @l`, { l: like });
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
