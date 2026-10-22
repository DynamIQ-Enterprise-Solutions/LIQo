import crypto from 'node:crypto';

export const ID_PATTERN = /^[A-Za-z0-9_-]{1,40}$/;

const ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyz';

export function newId(prefix) {
  const bytes = crypto.randomBytes(6);
  let s = '';
  for (const b of bytes) s += ALPHABET[b % 36];
  return `${prefix}-${s}`;
}

/**
 * Gives every element in a layout a fresh id and rewrites references
 * (openings → walls, connector endpoints → levels). Used when copying a map.
 */
export function regenerateIds(layout) {
  const map = new Map();
  const fresh = (oldId, prefix) => {
    if (!map.has(oldId)) map.set(oldId, newId(prefix));
    return map.get(oldId);
  };

  const out = structuredClone(layout);
  for (const b of out.buildings ?? []) {
    b.id = fresh(b.id, 'bd');
    for (const l of b.levels ?? []) {
      l.id = fresh(l.id, 'lv');
      for (const w of l.walls ?? []) w.id = fresh(w.id, 'w');
      for (const o of l.openings ?? []) {
        o.id = fresh(o.id, 'o');
        o.wall = fresh(o.wall, 'w');
      }
      for (const s of l.spaces ?? []) s.id = fresh(s.id, 'sp');
      for (const f of l.features ?? []) f.id = fresh(f.id, 'ft');
    }
  }
  for (const c of out.connectors ?? []) {
    c.id = fresh(c.id, 'cn');
    for (const e of c.endpoints ?? []) e.level = fresh(e.level, 'lv');
  }
  return out;
}
