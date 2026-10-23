// Option lists (store categories, unit types, floor labels) on Firestore (P1-06A).
//   branch_options/<id>, _unique/option:<branch>:<kind>:<name>  (SQL: UNIQUE (branch_id, kind, name))
import { col, docOf, runTx, nextId, one, all, uniqueRef, Timestamp } from '../../db/firestore.js';
import { KINDS } from '../shared/options.js';
import { compare, dupError, fkError } from './util.js';

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
    appCategory: row.app_category ?? 'other',
  };
}

async function withUse(rows) {
  const stores = await all(col('stores'));
  const use = new Map();
  for (const s of stores) if (s.category_id != null) use.set(s.category_id, (use.get(s.category_id) ?? 0) + 1);
  return rows.map((o) => ({ ...o, in_use: use.get(o.id) ?? 0 }));
}

export async function list({ branchId, kind, includeInactive }) {
  const rows = (await all(col('branch_options').where('branch_id', '==', Number(branchId))))
    .filter((o) => !kind || o.kind === kind)
    .filter((o) => includeInactive || o.is_active)
    .sort((a, b) => compare(a.kind, b.kind) || a.sort_order - b.sort_order || compare(a.name, b.name));
  return (await withUse(rows)).map(toPublic);
}

export async function findById(id) {
  const o = await one('branch_options', Number(id));
  return o ? toPublic((await withUse([o]))[0]) : null;
}

const guardOf = (branchId, kind, name) => uniqueRef('option', `${Number(branchId)}:${kind}:${String(name).trim()}`);

export async function create({ branchId, kind, name, sortOrder = 0 }) {
  const id = await runTx(async (tx) => {
    if (!(await tx.get(docOf('branches', branchId))).exists) throw fkError();
    const guard = guardOf(branchId, kind, name);
    if ((await tx.get(guard)).exists) throw dupError();
    const nid = await nextId('branch_options', tx);
    tx.set(guard, { id: nid });
    tx.set(docOf('branch_options', nid), { id: nid, branch_id: Number(branchId), kind, name, sort_order: sortOrder ?? 0, is_active: true, created_at: Timestamp.now(), updated_at: Timestamp.now() });
    return nid;
  });
  return findById(id);
}

export async function update(id, { name, sortOrder }) {
  await runTx(async (tx) => {
    const ref = docOf('branch_options', id);
    const cur = (await tx.get(ref)).data();
    if (cur.name.trim().toLowerCase() !== String(name).trim().toLowerCase()) {
      const guard = guardOf(cur.branch_id, cur.kind, name);
      if ((await tx.get(guard)).exists) throw dupError();
      tx.delete(guardOf(cur.branch_id, cur.kind, cur.name));
      tx.set(guard, { id: Number(id) });
    }
    tx.update(ref, { name, sort_order: sortOrder ?? 0, updated_at: Timestamp.now() });
  });
  return findById(id);
}

export async function setActive(id, active) {
  await docOf('branch_options', id).update({ is_active: !!active, updated_at: Timestamp.now() });
  return findById(id);
}

export async function remove(id) {
  await runTx(async (tx) => {
    const ref = docOf('branch_options', id);
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    // A category still used by a store cannot go (SQL: foreign key).
    const used = await tx.get(col('stores').where('category_id', '==', Number(id)).limit(1));
    if (!used.empty) throw fkError();
    const cur = snap.data();
    tx.delete(guardOf(cur.branch_id, cur.kind, cur.name));
    tx.delete(ref);
  });
}

/** Round 21: the shopper app's category for a store-category option. */
export async function setAppCategory(id, appCategory) {
  await docOf('branch_options', id).update({ app_category: appCategory, updated_at: Timestamp.now() });
  return findById(id);
}
