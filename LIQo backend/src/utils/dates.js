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
