// SQL Server helpers shared by the mssql repos (P1-06A).
import { sql } from './pool.js';

/** Builds "col IN (@p0,@p1,...)" plus the params object. Empty list → "1=0". */
export function inList(column, ids, prefix = 'p') {
  if (!ids || ids.length === 0) return { clause: '1=0', params: {} };
  const names = ids.map((_, i) => `@${prefix}${i}`);
  const params = Object.fromEntries(ids.map((id, i) => [`${prefix}${i}`, { type: sql.Int, value: id }]));
  return { clause: `${column} IN (${names.join(',')})`, params };
}
