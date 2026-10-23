import { query, sql } from '../../db/pool.js';

import { DEFAULTS, RULES } from '../shared/settings.js';

export { DEFAULTS, RULES };

let cache = null;
let cachedAt = 0;
const TTL_MS = 30_000;

export async function getAll() {
  if (cache && Date.now() - cachedAt < TTL_MS) return cache;
  try {
    const r = await query('SELECT setting_key, setting_value FROM platform_settings');
    const out = { ...DEFAULTS };
    for (const row of r.recordset) out[row.setting_key] = row.setting_value;
    cache = out;
    cachedAt = Date.now();
    return out;
  } catch (err) {
    console.error('settings read failed, using defaults:', err.message);
    return { ...DEFAULTS };
  }
}

export async function getText(key) {
  const all = await getAll();
  return String(all[key] ?? DEFAULTS[key] ?? '');
}

export async function getNumber(key) {
  const all = await getAll();
  const n = Number(all[key]);
  return Number.isFinite(n) ? n : Number(DEFAULTS[key]);
}

export async function setMany(values, updatedBy) {
  for (const [key, value] of Object.entries(values)) {
    await query(
      `MERGE platform_settings AS t
       USING (SELECT @k AS setting_key) AS s ON t.setting_key = s.setting_key
       WHEN MATCHED THEN UPDATE SET setting_value = @v, updated_by = @by, updated_at = SYSDATETIME()
       WHEN NOT MATCHED THEN INSERT (setting_key, setting_value, updated_by) VALUES (@k, @v, @by);`,
      { k: key, v: String(value), by: { type: sql.Int, value: updatedBy } },
    );
  }
  invalidate();
  return getAll();
}

export function invalidate() {
  cache = null;
}
