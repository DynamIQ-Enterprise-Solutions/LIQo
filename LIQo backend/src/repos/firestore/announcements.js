// Announcements on Firestore (P1-06A). The target branches are an array on
// the document (branch_ids) instead of the announcement_branches table; dates
// are 'yyyy-mm-dd' strings, which sort and compare like SQL DATEs.
import { col, docOf, getDb, runTx, nextId, one, all, Timestamp } from '../../db/firestore.js';
import { toDateOnly, todayDateOnly } from '../../utils/dates.js';
import { listInMemory, byId, compare, fkError } from './util.js';

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


async function lookups() {
  const [users, stores, branches, malls] = await Promise.all([all(col('users')), all(col('stores')), all(col('branches')), all(col('malls'))]);
  return { users: byId(users), stores: byId(stores), branches: byId(branches), malls: byId(malls) };
}

function shape(a, lk) {
  const row = {
    ...a,
    store_name: a.store_id != null ? lk.stores.get(a.store_id)?.name ?? null : null,
    created_by_name: lk.users.get(a.created_by)?.full_name ?? null,
    reviewed_by_name: a.reviewed_by != null ? lk.users.get(a.reviewed_by)?.full_name ?? null : null,
  };
  const branches = (a.branch_ids ?? [])
    .map((id) => lk.branches.get(id))
    .filter(Boolean)
    .map((b) => ({ id: b.id, name: b.name, mallName: lk.malls.get(b.mall_id)?.name ?? null }))
    .sort((x, y) => compare(x.mallName, y.mallName) || compare(x.name, y.name));
  return { row, branches };
}

/**
 * visibility: { all } | { branchIds, includePendingReview } | { ownerId, storeIds }
 */
export async function list({ search, status, live, offset, pageSize, sortColumn, sortOrder, visibility }) {
  const [rows, lk] = await Promise.all([all(col('announcements')), lookups()]);
  const today = todayDateOnly();
  const vis = visibility.all ? null : new Set((visibility.branchIds ?? []).map(Number));
  const shaped = rows
    .filter((a) => {
      if (!vis) return true;
      const inBranches = (a.branch_ids ?? []).some((b) => vis.has(b));
      // Store owner: own submissions + approved items for the branches of their stores.
      if (visibility.ownerId != null) return a.created_by === Number(visibility.ownerId) || (a.status === 'approved' && inBranches);
      return inBranches;
    })
    .filter((a) => !status || a.status === status)
    .filter((a) => live !== 'live' || (a.status === 'approved' && a.starts_on <= today && a.ends_on >= today))
    .map((a) => shape(a, lk));
  const { items, totalCount } = listInMemory(
    shaped.map((s) => ({ ...s.row, _branches: s.branches })),
    { search, searchFields: ['title', 'body', 'created_by_name', 'store_name'], sortColumn, sortOrder, offset, pageSize },
  );
  return { items: items.map((r) => toPublic(r, r._branches)), totalCount };
}

export async function findById(id) {
  const a = await one('announcements', Number(id));
  if (!a) return null;
  const { row, branches } = shape(a, await lookups());
  return toPublic(row, branches);
}

async function checkBranches(tx, branchIds) {
  for (const b of branchIds) if (!(await tx.get(docOf('branches', b))).exists) throw fkError();
}

export async function create({ title, body, imageUrl, startsOn, endsOn, status, storeId, createdBy, createdRole, branchIds }) {
  const id = await runTx(async (tx) => {
    await checkBranches(tx, branchIds);
    const nid = await nextId('announcements', tx);
    tx.set(docOf('announcements', nid), {
      id: nid,
      title,
      body,
      image_url: imageUrl ?? null,
      starts_on: toDateOnly(startsOn),
      ends_on: toDateOnly(endsOn),
      status,
      store_id: storeId ?? null,
      created_by: createdBy,
      created_role: createdRole,
      reviewed_by: null,
      reviewed_at: null,
      reject_reason: null,
      branch_ids: [...new Set(branchIds.map(Number))],
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    return nid;
  });
  return findById(id);
}

export async function update(id, { title, body, imageUrl, startsOn, endsOn, branchIds, status }) {
  await runTx(async (tx) => {
    if (branchIds) await checkBranches(tx, branchIds);
    const patch = { title, body, image_url: imageUrl ?? null, starts_on: toDateOnly(startsOn), ends_on: toDateOnly(endsOn), updated_at: Timestamp.now() };
    if (status) patch.status = status;
    if (branchIds) patch.branch_ids = [...new Set(branchIds.map(Number))];
    tx.update(docOf('announcements', id), patch);
  });
  return findById(id);
}

export async function review(id, { status, reviewedBy, reason }) {
  await docOf('announcements', id).update({ status, reviewed_by: reviewedBy, reviewed_at: Timestamp.now(), reject_reason: reason ?? null, updated_at: Timestamp.now() });
  return findById(id);
}

/** Takes some branches off an announcement's targets (it stays for the others). */
export async function removeBranches(id, branchIds) {
  if (!branchIds.length) return findById(id);
  const drop = new Set(branchIds.map(Number));
  await runTx(async (tx) => {
    const ref = docOf('announcements', id);
    const cur = (await tx.get(ref)).data();
    tx.update(ref, { branch_ids: (cur.branch_ids ?? []).filter((b) => !drop.has(b)), updated_at: Timestamp.now() });
  });
  return findById(id);
}

export async function remove(id) {
  await docOf('announcements', id).delete();
}

/** Round 21: sets or clears (null) the announcement's uploaded picture. */
export async function setImage(id, key, mime) {
  await docOf('announcements', id).update({ image_key: key ?? null, image_mime: mime ?? null, updated_at: Timestamp.now() });
  return findById(id);
}
