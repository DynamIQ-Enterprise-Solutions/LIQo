// Who owns and manages what, on Firestore (P1-06A). Documents mirror the SQL rows:
//   supervisor_assignments/<id>     { user_id, mall_id | branch_id, assigned_by, assigned_at }
//   mall_admin_assignments/<u>_<b>  { user_id, branch_id, ... }   (SQL: UNIQUE (user_id, branch_id))
import { col, docOf, getDb, runTx, nextId, all, Timestamp } from '../../db/firestore.js';
import { byId, compare, fkError } from './util.js';

export const ONE_BRANCH = 'ONE_BRANCH';

const lookups = async () => {
  const [malls, branches] = await Promise.all([all(col('malls')), all(col('branches'))]);
  return { malls: byId(malls), branches: byId(branches) };
};

export async function supervisorAssignments(userId) {
  const [rows, { malls, branches }] = await Promise.all([all(col('supervisor_assignments').where('user_id', '==', Number(userId))), lookups()]);
  const full = rows.map((x) => {
    const b = x.branch_id != null ? branches.get(x.branch_id) : null;
    return { ...x, mall_name: x.mall_id != null ? malls.get(x.mall_id)?.name : null, branch_name: b?.name ?? null, branch_mall_name: b ? malls.get(b.mall_id)?.name : null };
  });
  full.sort((a, b) => compare(a.mall_name, b.mall_name) || compare(a.branch_mall_name, b.branch_mall_name) || compare(a.branch_name, b.branch_name));
  return {
    malls: full.filter((x) => x.mall_id != null).map((x) => ({ id: x.mall_id, name: x.mall_name })),
    branches: full.filter((x) => x.branch_id != null).map((x) => ({ id: x.branch_id, name: x.branch_name, mallName: x.branch_mall_name })),
  };
}

/** Replace a supervisor's whole assignment set in one transaction. */
export async function replaceSupervisorAssignments(userId, { mallIds, branchIds }, assignedBy) {
  const uid = Number(userId);
  await runTx(async (tx) => {
    const old = await tx.get(col('supervisor_assignments').where('user_id', '==', uid));
    for (const m of mallIds) if (!(await tx.get(docOf('malls', m))).exists) throw fkError();
    for (const b of branchIds) if (!(await tx.get(docOf('branches', b))).exists) throw fkError();
    const ids = [];
    for (let i = 0; i < mallIds.length + branchIds.length; i++) ids.push(await nextId('supervisor_assignments', tx));
    old.docs.forEach((d) => tx.delete(d.ref));
    let k = 0;
    for (const mallId of mallIds) {
      const id = ids[k++];
      tx.set(docOf('supervisor_assignments', id), { id, user_id: uid, mall_id: Number(mallId), branch_id: null, assigned_by: assignedBy ?? null, assigned_at: Timestamp.now() });
    }
    for (const branchId of branchIds) {
      const id = ids[k++];
      tx.set(docOf('supervisor_assignments', id), { id, user_id: uid, mall_id: null, branch_id: Number(branchId), assigned_by: assignedBy ?? null, assigned_at: Timestamp.now() });
    }
  });
  return supervisorAssignments(userId);
}

/**
 * Applies the "reports to" rule to every mall admin (see utils/ownership.js):
 * own branch's owner, else the mall's whole-mall owner, first linked, active
 * owners only, else none. Returns the admins whose superior changed.
 */
export async function recomputeReportsTo() {
  const [users, ma, sa, branches] = await Promise.all([all(col('users')), all(col('mall_admin_assignments')), all(col('supervisor_assignments')), all(col('branches'))]);
  const usersById = byId(users);
  const branchMall = new Map(branches.map((b) => [b.id, b.mall_id]));
  const activeOwner = (id) => usersById.get(id)?.role === 'supervisor' && usersById.get(id)?.is_active;
  const changed = [];
  const batch = getDb().batch();
  for (const u of users.filter((x) => x.role === 'mall_admin')) {
    const candidates = [];
    for (const a of ma.filter((x) => x.user_id === u.id)) {
      for (const s of sa) {
        if (!activeOwner(s.user_id)) continue;
        if (s.branch_id != null && s.branch_id === a.branch_id) candidates.push({ owner: s.user_id, pri: 0, at: s.assigned_at, id: s.id });
        if (s.mall_id != null && s.mall_id === branchMall.get(a.branch_id)) candidates.push({ owner: s.user_id, pri: 1, at: s.assigned_at, id: s.id });
      }
    }
    candidates.sort((x, y) => x.pri - y.pri || compare(x.at, y.at) || x.id - y.id);
    const to = candidates[0]?.owner ?? null;
    if ((u.reports_to ?? null) !== to) {
      batch.update(docOf('users', u.id), { reports_to: to, updated_at: Timestamp.now() });
      changed.push({ id: u.id, from: u.reports_to ?? null, to });
    }
  }
  if (changed.length) await batch.commit();
  return changed;
}

/** Everyone working on one mall: owners (whole-mall or branch-level) and admins with their branches here. */
export async function mallPeople(mallId) {
  const mid = Number(mallId);
  const [users, sa, ma, branches] = await Promise.all([all(col('users')), all(col('supervisor_assignments')), all(col('mall_admin_assignments')), all(col('branches'))]);
  const usersById = byId(users);
  const branchesById = byId(branches);
  const ownerIds = new Set(sa.filter((s) => s.mall_id === mid || branchesById.get(s.branch_id)?.mall_id === mid).map((s) => s.user_id));
  const owners = [...ownerIds]
    .map((id) => {
      const u = usersById.get(id);
      const mine = sa.filter((s) => s.user_id === id);
      const branchNames = mine
        .filter((s) => s.branch_id != null && branchesById.get(s.branch_id)?.mall_id === mid)
        .map((s) => branchesById.get(s.branch_id).name)
        .join(', ');
      return { id, fullName: u?.full_name, email: u?.email, isActive: !!u?.is_active, wholeMall: mine.some((s) => s.mall_id === mid), branchNames };
    })
    .sort((a, b) => Number(b.wholeMall) - Number(a.wholeMall) || compare(a.fullName, b.fullName));
  const adminRows = ma
    .filter((a) => branchesById.get(a.branch_id)?.mall_id === mid)
    .map((a) => ({ a, u: usersById.get(a.user_id), b: branchesById.get(a.branch_id) }))
    .sort((x, y) => compare(x.u?.full_name, y.u?.full_name) || compare(x.b?.name, y.b?.name));
  const byAdmin = new Map();
  for (const { u, b } of adminRows) {
    const entry = byAdmin.get(u.id) ?? {
      id: u.id,
      fullName: u.full_name,
      email: u.email,
      isActive: !!u.is_active,
      mustChangePassword: !!u.must_change_password,
      reportsTo: u.reports_to == null ? null : { id: u.reports_to, name: usersById.get(u.reports_to)?.full_name ?? null },
      branches: [],
    };
    entry.branches.push({ id: b.id, name: b.name });
    byAdmin.set(u.id, entry);
  }
  return { owners, admins: [...byAdmin.values()] };
}

/** Whole-mall ownership for an existing owner account. */
export async function addMallOwner(mallId, userId, assignedBy) {
  await runTx(async (tx) => {
    const existing = await tx.get(col('supervisor_assignments').where('user_id', '==', Number(userId)).where('mall_id', '==', Number(mallId)));
    if (!existing.empty) return;
    if (!(await tx.get(docOf('malls', mallId))).exists) throw fkError();
    const id = await nextId('supervisor_assignments', tx);
    tx.set(docOf('supervisor_assignments', id), { id, user_id: Number(userId), mall_id: Number(mallId), branch_id: null, assigned_by: assignedBy ?? null, assigned_at: Timestamp.now() });
  });
}

/** Removes this mall (whole-mall row and single branches of it) from an owner. The caller re-applies the reports-to rule. */
export async function removeMallOwner(mallId, userId) {
  const mid = Number(mallId);
  const [rows, branches] = await Promise.all([all(col('supervisor_assignments').where('user_id', '==', Number(userId))), all(col('branches').where('mall_id', '==', mid))]);
  const mallBranches = new Set(branches.map((b) => b.id));
  const batch = getDb().batch();
  for (const r of rows) if (r.mall_id === mid || mallBranches.has(r.branch_id)) batch.delete(docOf('supervisor_assignments', r.id));
  await batch.commit();
}

/** Replaces an admin's branches inside one mall only; branches of other malls are kept. */
export async function setMallAdminBranches(mallId, adminId, branchIds, assignedBy) {
  const mallBranches = (await all(col('branches').where('mall_id', '==', Number(mallId)))).map((b) => b.id);
  const outside = branchIds.filter((id) => !mallBranches.includes(id));
  if (outside.length) throw new Error('BRANCH_NOT_IN_MALL');
  const current = await mallAdminAssignments(adminId);
  const keep = current.branches.map((b) => b.id).filter((id) => !mallBranches.includes(id));
  if (keep.length && branchIds.length) throw new Error('ALREADY_ELSEWHERE');
  return replaceMallAdminAssignments(adminId, { branchIds: [...new Set([...keep, ...branchIds])] }, assignedBy);
}

/** Drops this mall's branches from an admin. The caller re-applies the reports-to rule. */
export async function removeMallAdmin(mallId, adminId, assignedBy) {
  return setMallAdminBranches(mallId, adminId, [], assignedBy);
}

export async function mallAdminAssignments(userId) {
  const [rows, { malls, branches }] = await Promise.all([all(col('mall_admin_assignments').where('user_id', '==', Number(userId))), lookups()]);
  const out = rows
    .map((x) => {
      const b = branches.get(x.branch_id);
      return { id: x.branch_id, name: b?.name ?? null, mallId: b?.mall_id ?? null, mallName: b ? malls.get(b.mall_id)?.name ?? null : null };
    })
    .sort((a, b) => compare(a.mallName, b.mallName) || compare(a.name, b.name));
  return { branches: out };
}

export async function replaceMallAdminAssignments(userId, { branchIds }, assignedBy) {
  if (branchIds.length > 1) throw new Error(ONE_BRANCH);
  const uid = Number(userId);
  await runTx(async (tx) => {
    const old = await tx.get(col('mall_admin_assignments').where('user_id', '==', uid));
    for (const b of branchIds) if (!(await tx.get(docOf('branches', b))).exists) throw fkError();
    old.docs.forEach((d) => tx.delete(d.ref));
    for (const branchId of branchIds) {
      tx.set(docOf('mall_admin_assignments', `${uid}_${Number(branchId)}`), { user_id: uid, branch_id: Number(branchId), assigned_by: assignedBy ?? null, assigned_at: Timestamp.now() });
    }
  });
  return mallAdminAssignments(userId);
}

/** The mall admins placed on one branch (several are allowed). */
export async function branchAdmins(branchId) {
  const [rows, users] = await Promise.all([all(col('mall_admin_assignments').where('branch_id', '==', Number(branchId))), all(col('users'))]);
  const usersById = byId(users);
  return rows
    .map((x) => usersById.get(x.user_id))
    .filter(Boolean)
    .map((u) => ({ id: u.id, fullName: u.full_name, isActive: !!u.is_active }))
    .sort((a, b) => compare(a.fullName, b.fullName));
}
