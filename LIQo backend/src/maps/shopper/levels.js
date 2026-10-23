// Package levels for the shopper app (docs/shopper-package-format.md §1–§2):
// editor levels at the same elevation become one package level, ordered lowest
// to highest; each gets a short label of at most 3 characters worked out from
// its name ("Ground floor" → G, "Level 2" → 2, "Basement 1" → B1), where a
// matching floor-label option of the branch wins. Pure.

const WORDS = [
  [/\b(lower\s*ground|lg)\b/i, 'LG'],
  [/\b(upper\s*ground|ug)\b/i, 'UG'],
  [/\b(ground|gf)\b/i, 'G'],
  [/\b(mezzanine|mezz)\b/i, 'M'],
  [/\b(roof\s*deck|rooftop|roof)\b/i, 'R'],
];
const ORDINALS = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth'];
const PREFIXED = [
  [/\b(basement|b)\s*(\d{1,2})\b/i, 'B'],
  [/\b(parking|p)\s*(\d{1,2})\b/i, 'P'],
];

/**
 * The short label for a level name. [floorLabels] are the branch's floor-label
 * option names; one of at most 3 characters that appears as a word in the
 * level name wins ("Upper ground (UG)" with option "UG" → UG).
 */
export function shortOf(name, floorLabels = []) {
  const text = String(name ?? '').trim();
  for (const label of floorLabels) {
    const l = String(label ?? '').trim();
    if (!l || l.length > 3) continue;
    const esc = l.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (new RegExp(`(^|[^A-Za-z0-9])${esc}($|[^A-Za-z0-9])`, 'i').test(text)) return l.toUpperCase();
  }
  if (text.length && text.length <= 3) return text.toUpperCase();
  for (const [re, prefix] of PREFIXED) {
    const m = re.exec(text);
    if (m) return `${prefix}${Number(m[2])}`.slice(0, 3);
  }
  if (/\bbasement\b/i.test(text)) return 'B';
  for (const [re, short] of WORDS) if (re.test(text)) return short;
  const n = /(\d{1,3})/.exec(text);
  if (n) return String(Number(n[1])).slice(0, 3);
  const ordinal = ORDINALS.findIndex((w) => new RegExp(`\\b${w}\\b`, 'i').test(text));
  if (ordinal >= 0) return String(ordinal + 1);
  const initials = text
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w[0].toUpperCase())
    .join('');
  return (initials || '?').slice(0, 3);
}

/**
 * Package levels from a layout: [{lv, elevation, editorLevels:[{building, level}], name, short, height, ground}],
 * lowest first. Levels at the same elevation (to the centimetre) merge; the
 * first building's level (by building order, then level order) gives the name.
 * Exactly one level is the ground: the one whose elevation is closest to 0, the lower on a tie.
 */
export function packageLevels(layout, floorLabels = []) {
  const groups = new Map();
  for (const b of layout?.buildings ?? []) {
    for (const l of b.levels ?? []) {
      const key = Math.round((l.elevation ?? 0) * 100);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push({ building: b, level: l });
    }
  }
  const levels = [...groups.entries()]
    .sort(([a], [b]) => a - b)
    .map(([key, editorLevels], lv) => {
      const first = editorLevels[0].level;
      return {
        lv,
        elevation: key / 100,
        editorLevels,
        id: first.id,
        name: first.name,
        short: shortOf(first.name, floorLabels),
        height: Math.max(...editorLevels.map((e) => e.level.height ?? 4)),
        ground: false,
      };
    });
  if (levels.length) {
    let best = levels[0];
    for (const l of levels) if (Math.abs(l.elevation) < Math.abs(best.elevation)) best = l;
    best.ground = true;
  }
  return levels;
}

/** Editor level id → package level, for a layout. */
export function levelIndex(levels) {
  const out = new Map();
  for (const l of levels) for (const e of l.editorLevels) out.set(e.level.id, l);
  return out;
}

/** Space id → its package level's short label (for the directory's store list). */
export function spaceFloors(layout, floorLabels = []) {
  const levels = packageLevels(layout, floorLabels);
  const out = new Map();
  for (const l of levels) for (const e of l.editorLevels) for (const s of e.level.spaces ?? []) out.set(s.id, l.short);
  return out;
}
