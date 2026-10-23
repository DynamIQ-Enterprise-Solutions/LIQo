// Date-only helpers. DATE columns travel as 'yyyy-MM-dd' strings, never as
// timestamps, so a date never shifts by a day across timezones.

export function toDateOnly(value) {
  if (value == null) return null;
  if (typeof value === 'string') return value.slice(0, 10);
  const d = value;
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** 'yyyy-MM-dd' → local-midnight Date for binding to a sql.Date parameter. */
export function fromDateOnly(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text));
  if (!m) return null;
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

export function todayDateOnly() {
  return toDateOnly(new Date());
}

// ---- Philippine time (UTC+8, no daylight saving), for the shopper app (Round 21) ----

const PH_MS = 8 * 3600 * 1000;

/** Today's date in the Philippines, 'yyyy-MM-dd'. */
export function phToday(now = new Date()) {
  return new Date(now.getTime() + PH_MS).toISOString().slice(0, 10);
}

/** A moment as ISO 8601 with the Philippine offset: '2026-10-23T10:15:00+08:00'. */
export function phIso(value) {
  if (value == null) return null;
  const d = value instanceof Date ? value : new Date(value);
  return `${new Date(d.getTime() + PH_MS).toISOString().slice(0, 19)}+08:00`;
}

/** Adds [days] to a 'yyyy-MM-dd' date. */
export function addDays(dateOnly, days) {
  const d = new Date(`${dateOnly}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
