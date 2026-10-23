// Small helpers shared by the Firestore repos (P1-06A).

/** The field a SQL sort fragment names ("u.full_name" → "full_name"). */
export const fieldOf = (sortColumn) => String(sortColumn || 'id').split('.').pop().trim();

/** Search (case-insensitive contains on [searchFields]), sort and page rows in memory, like the SQL lists. */
export function listInMemory(rows, { search = '', searchFields = [], sortColumn = 'id', sortOrder = 'ASC', offset = 0, pageSize = 20, sortMap = {} }) {
  const q = String(search || '').trim().toLowerCase();
  let out = q ? rows.filter((r) => searchFields.some((f) => String(r[f] ?? '').toLowerCase().includes(q))) : rows.slice();
  const field = sortMap[sortColumn] ?? fieldOf(sortColumn);
  const dir = String(sortOrder).toUpperCase() === 'DESC' ? -1 : 1;
  out.sort((a, b) => dir * compare(a[field], b[field]) || compare(a.id, b.id));
  return { items: out.slice(offset, offset + pageSize), totalCount: out.length };
}

export function compare(a, b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a instanceof Date || b instanceof Date) return new Date(a) - new Date(b);
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  if (typeof a === 'boolean' || typeof b === 'boolean') return Number(a) - Number(b);
  return String(a).localeCompare(String(b), undefined, { sensitivity: 'base' });
}

/** Rows of a collection keyed by id. */
export const byId = (rows) => new Map(rows.map((r) => [r.id, r]));

/** Count of an id list in a scope list (null = no limit). */
export const inScope = (ids, id) => !ids || ids.map(Number).includes(Number(id));

/** The SQL Server error numbers routes already understand, so they work unchanged on Firestore. */
export function dupError(what = 'DUPLICATE') {
  const e = new Error(what);
  e.number = 2627; // unique key
  return e;
}
export function fkError(what = 'FOREIGN_KEY') {
  const e = new Error(what);
  e.number = 547; // missing linked record
  return e;
}
