// Opening hours (Round 21, owner decisions 2026-10-23; shape in
// docs/shopper-package-format.md §7). Philippine time, 24-hour "HH:MM",
// "24:00" = midnight at the end of the day, a close at or before the open
// runs past midnight, one range per weekday (no split days), special days
// override the week on their date.
import { z } from 'zod';

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$|^24:00$/, 'Use a time like 09:30 (24-hour), or 24:00 for midnight.');
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use a date like 2026-12-25.');
const note = z.string().trim().max(40, 'Keep the note under 40 characters.');

const weekRow = z.object({
  day: z.number().int().min(1, 'Days run 1 (Monday) to 7 (Sunday).').max(7, 'Days run 1 (Monday) to 7 (Sunday).'),
  open: time,
  close: time,
});

const special = z.union([
  z.object({ date, closed: z.literal(true), note: note.optional() }),
  z.object({ date, open: time, close: time, note: note.optional() }),
]);

export const hoursSchema = z
  .object({
    week: z.array(weekRow).max(7),
    specials: z.array(special).max(60, 'Keep at most 60 special days.').default([]),
  })
  .superRefine((h, ctx) => {
    const days = new Set();
    for (const r of h.week) {
      if (days.has(r.day)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Each weekday has one opening time at most.', path: ['week'] });
      days.add(r.day);
      if (r.open === r.close) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Opening and closing times must differ.', path: ['week'] });
    }
    const dates = new Set();
    for (const s of h.specials) {
      if (dates.has(s.date)) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${s.date} is listed twice.`, path: ['specials'] });
      dates.add(s.date);
      if (!s.closed && s.open === s.close) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Opening and closing times must differ.', path: ['specials'] });
    }
  });

/** Hours in the stored order: weekdays 1..7, special days by date, notes left out when empty. */
export function normaliseHours(h) {
  if (h == null) return null;
  return {
    week: [...h.week].sort((a, b) => a.day - b.day).map(({ day, open, close }) => ({ day, open, close })),
    specials: [...(h.specials ?? [])]
      .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
      .map((s) => {
        const out = s.closed ? { date: s.date, closed: true } : { date: s.date, open: s.open, close: s.close };
        if (s.note) out.note = s.note;
        return out;
      }),
  };
}

/** Stored JSON text → hours, or null (tolerates a damaged value). */
export function parseHours(text) {
  if (!text) return null;
  try {
    const parsed = hoursSchema.safeParse(JSON.parse(text));
    return parsed.success ? normaliseHours(parsed.data) : null;
  } catch {
    return null;
  }
}

export const hoursText = (h) => (h == null ? null : JSON.stringify(normaliseHours(h)));

export const STORE_STATUSES = ['open', 'temporarily_closed', 'being_repaired', 'opening_soon'];
export const APP_CATEGORIES = ['food', 'fashion', 'tech', 'books', 'services', 'other'];
