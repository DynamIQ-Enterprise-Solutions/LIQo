// Platform settings on Firestore (P1-06A): one doc per key in platform_settings.
import { col, docOf, getDb, FieldValue } from '../../db/firestore.js';
import { DEFAULTS, RULES } from '../shared/settings.js';

export { DEFAULTS, RULES };

let cache = null;
let cachedAt = 0;
const TTL_MS = 30_000;

export async function getAll() {
  if (cache && Date.now() - cachedAt < TTL_MS) return cache;
  try {
    const snap = await col('platform_settings').get();
    const out = { ...DEFAULTS };
    for (const d of snap.docs) out[d.id] = d.data().setting_value;
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
  const batch = getDb().batch();
  for (const [key, value] of Object.entries(values)) {
    batch.set(docOf('platform_settings', key), { setting_key: key, setting_value: String(value), updated_by: updatedBy ?? null, updated_at: FieldValue.serverTimestamp() });
  }
  await batch.commit();
  invalidate();
  return getAll();
}

export function invalidate() {
  cache = null;
}
