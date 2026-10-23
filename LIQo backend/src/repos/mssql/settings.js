import { query, sql } from '../../db/pool.js';

// Safe defaults used when a row is missing or the DB read fails.
export const DEFAULTS = Object.freeze({
  min_password_length: '8',
  ai_file_size_mb: '15',
  ai_daily_cap: '20', // not enforced since Round 15 (only the gateway wallet limits AI); kept for later
  ai_model: '', // IQGateway model for floor-plan reading; chosen by a superadmin from the gateway's list
  ai_wallet_full: '', // the wallet balance right after the last top-up (the credit bar's full mark); kept by GET /ai/status
  ai_wallet_last: '', // the balance last seen, to notice a top-up (the balance went up)
  ai_start_credits: '3', // AI credits a new mall admin starts with (Round 19; as far as the wallet has free credits)
  ai_credit_cap: '20', // the most AI credits one mall admin may hold (Round 19)
  default_announcement_days: '7',
  session_timeout_hours: '8',
  max_login_attempts: '5',
});

// Allowed ranges, enforced on update.
export const RULES = Object.freeze({
  min_password_length: { min: 6, max: 64, label: 'Minimum password length' },
  ai_file_size_mb: { min: 1, max: 100, label: 'AI file size limit (MB)' },
  default_announcement_days: { min: 1, max: 365, label: 'Default announcement duration (days)' },
  session_timeout_hours: { min: 1, max: 72, label: 'Session timeout (hours)' },
  max_login_attempts: { min: 3, max: 20, label: 'Max failed sign-ins before lockout' },
  ai_start_credits: { min: 0, max: 1000, label: 'Starting AI credits for a new mall admin' },
  ai_credit_cap: { min: 1, max: 10000, label: 'Most AI credits per mall admin' },
});

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
