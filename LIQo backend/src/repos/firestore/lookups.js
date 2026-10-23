// The picker lookups behind GET /lookups/:name on Firestore (P1-06A): the same
// names, labels, filters and scopes as mssql/lookups.js, done in memory.
import { col, all } from '../../db/firestore.js';
import { byId, compare } from './util.js';

const inIds = (ids, id) => (ids ?? []).map(Number).includes(Number(id));
const person = (u) => `${u.full_name} (${u.email})`;

/** Each lookup: rows(scope) → [{ id, label, active, parent? }] already filtered by its fixed rule and scope. */
export const LOOKUPS = {
  async malls(scope) {
    return (await all(col('malls')))
      .filter((m) => scope.all || inIds(scope.mallIds, m.id))
      .map((m) => ({ id: m.id, label: m.name, active: !!m.is_active }));
  },
  async branches(scope) {
    const [branches, malls] = await Promise.all([all(col('branches')), all(col('malls'))]);
    const mall = byId(malls);
    return branches
      .filter((b) => mall.get(b.mall_id)?.is_active)
      .filter((b) => scope.all || inIds(scope.branchIds, b.id))
      .map((b) => ({ id: b.id, label: `${mall.get(b.mall_id).name} · ${b.name}`, active: !!b.is_active, parent: b.mall_id }));
  },
  async supervisors(scope) {
    if (!scope.all) return [];
    return (await all(col('users').where('role', '==', 'supervisor'))).map((u) => ({ id: u.id, label: person(u), active: !!u.is_active }));
  },
  // Mall admins with no branch yet: the only ones a mall may take on (one branch per admin).
  async free_mall_admins(scope) {
    if (!scope.all) return [];
    const [users, links] = await Promise.all([all(col('users').where('role', '==', 'mall_admin')), all(col('mall_admin_assignments'))]);
    const placed = new Set(links.map((l) => l.user_id));
    return users.filter((u) => !placed.has(u.id)).map((u) => ({ id: u.id, label: person(u), active: !!u.is_active }));
  },
  async stores(scope) {
    const [stores, branches, malls] = await Promise.all([all(col('stores')), all(col('branches')), all(col('malls'))]);
    const branch = byId(branches);
    const mall = byId(malls);
    return stores
      .filter((s) => branch.get(s.branch_id)?.is_active && mall.get(branch.get(s.branch_id).mall_id)?.is_active)
      .filter((s) => scope.all || inIds(scope.branchIds, s.branch_id))
      .map((s) => ({ id: s.id, label: `${branch.get(s.branch_id).name} · ${s.name}`, active: !!s.is_active, parent: s.branch_id }));
  },
  async store_categories(scope) {
    return (await all(col('branch_options').where('kind', '==', 'store_category')))
      .filter((o) => scope.all || inIds(scope.branchIds, o.branch_id))
      .map((o) => ({ id: o.id, label: o.name, active: !!o.is_active, parent: o.branch_id }));
  },
  async mall_admins(scope) {
    const users = await all(col('users').where('role', '==', 'mall_admin'));
    let allowed = null;
    if (!scope.all) {
      const links = await all(col('mall_admin_assignments'));
      allowed = new Set(links.filter((l) => inIds(scope.branchIds, l.branch_id)).map((l) => l.user_id));
    }
    return users.filter((u) => !allowed || allowed.has(u.id)).map((u) => ({ id: u.id, label: person(u), active: !!u.is_active }));
  },
};

/** One page of a lookup, scoped; null for an unknown name. */
export async function lookup(name, { scope, search, parentId, includeInactive, page, pageSize }) {
  const rows = Object.hasOwn(LOOKUPS, name) ? await LOOKUPS[name](scope) : null;
  if (!rows) return null;
  const q = String(search || '').toLowerCase();
  const out = rows
    .filter((r) => includeInactive || r.active)
    .filter((r) => !q || r.label.toLowerCase().includes(q))
    .filter((r) => !parentId || r.parent === undefined || r.parent === Number(parentId))
    .sort((a, b) => compare(a.label, b.label) || a.id - b.id);
  const offset = (page - 1) * pageSize;
  return { items: out.slice(offset, offset + pageSize).map((r) => ({ id: r.id, label: r.label, isActive: r.active })), totalCount: out.length };
}
