// Builds the live pipeline page's data from FEATURE_PIPELINE.md.
//
//   node tool/pipeline-data.mjs          writes tool/pipeline-data.json
//
// The page (https://claude.ai/artifact/8QeFNHg6Xhp1jSQaMsSUx1) reads that JSON
// from its database document pipeline/current. The project hook
// (tool/pipeline-hook.mjs) runs this after every edit of FEATURE_PIPELINE.md
// and tells the session to push the result. Nothing here is typed by hand:
// change the markdown, never the JSON.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const SOURCE = path.join(ROOT, 'FEATURE_PIPELINE.md');
export const OUTPUT = path.join(ROOT, 'tool', 'pipeline-data.json');

const STATUSES = ['PLANNED', 'IN PROGRESS', 'BLOCKED', 'DONE'];
const ID = /P\d-\d{2}[A-Z]?/g;

// Markdown → plain text for the page.
const clean = (s) => s.replace(/`/g, '').replace(/\*\*/g, '').replace(/\s+/g, ' ').trim();

export function buildPipelineData(markdown) {
  const errors = [];
  const archiveAt = markdown.indexOf('## 6. Completed Archive');
  if (archiveAt < 0) errors.push('Section "## 6. Completed Archive" not found.');

  // Entries: "#### <ID> — <Name>", then the attribute table, then an optional checklist.
  const entries = [];
  const heading = /^#### (P\d-\d{2}[A-Z]?) — (.+)$/gm;
  const starts = [...markdown.matchAll(heading)];
  starts.forEach((m, i) => {
    const end = i + 1 < starts.length ? starts[i + 1].index : markdown.length;
    const block = markdown.slice(m.index, end).split(/^##{1,2} /m)[0];
    const rows = Object.fromEntries(
      [...block.matchAll(/^\| ([^|]+?) \| (.*) \|$/gm)].map((r) => [r[1].trim(), r[2].trim()]),
    );
    const id = m[1];
    const status = clean(rows.Status ?? '');
    if (!STATUSES.includes(status) && !/^CANCELLED \(.+\)$/.test(status)) {
      errors.push(`${id}: status "${status}" is not in the legend.`);
    }
    const items = [...block.matchAll(/^- \[( |x)\] (.+)$/gm)].map((it) => {
      const text = clean(it[2]);
      const owner = /^Owner:\s*/i.test(text);
      return { text: owner ? text.replace(/^Owner:\s*/i, '') : text, done: it[1] === 'x', owner };
    });
    const archived = archiveAt >= 0 && m.index > archiveAt;
    if (!archived && status !== 'DONE' && !items.some((x) => !x.done)) {
      errors.push(`${id}: active entry has no open checklist item ("- [ ] ...") saying what is left.`);
    }
    entries.push({
      id,
      name: clean(m[2]),
      tier: clean(rows.Tier ?? id.slice(0, 2)),
      status,
      effort: clean(rows.Effort ?? ''),
      description: clean(rows.Description ?? ''),
      prd: (rows['PRD / Blueprint'] ?? '').match(/PRD §[\d.]+/)?.[0] ?? '',
      deps: [...new Set((rows.Dependencies ?? '').match(ID) ?? [])],
      items,
      archived,
    });
  });

  const ids = new Set();
  for (const e of entries) {
    if (ids.has(e.id)) errors.push(`${e.id}: duplicate ID.`);
    ids.add(e.id);
    if (e.archived !== (e.status === 'DONE')) {
      errors.push(`${e.id}: ${e.archived ? 'sits in §6 but is not DONE' : 'is DONE but still sits in §3; move it to §6'}.`);
    }
  }
  for (const e of entries) for (const d of e.deps) if (!ids.has(d)) errors.push(`${e.id}: depends on unknown ${d}.`);

  // §6 summary table: | ID | Feature | Shipped in | What changed from the plan |
  const changed = {};
  if (archiveAt >= 0) {
    const archive = markdown.slice(archiveAt).split(/^### /m)[0];
    for (const r of archive.matchAll(/^\| (P\d-\d{2}[A-Z]?) \| (.+?) \| (.+?) \| (.+) \|$/gm)) {
      changed[r[1]] = { shippedIn: clean(r[3]), changed: clean(r[4]) };
    }
  }
  for (const e of entries) if (e.archived) Object.assign(e, changed[e.id] ?? { shippedIn: '', changed: '' });

  // §4 build order: the numbered list after "**Build order (what is next):**".
  const steps = [];
  const orderAt = markdown.indexOf('**Build order (what is next):**');
  if (orderAt < 0) errors.push('"**Build order (what is next):**" not found in §4.');
  else {
    const lines = markdown.slice(orderAt).split(/\r?\n/).slice(1);
    for (const line of lines) {
      const s = line.match(/^\d+\. (.+)$/);
      if (s) steps.push(clean(s[1]));
      else if (steps.length && line.trim() !== '') break;
    }
    if (!steps.length) errors.push('The build order has no numbered steps.');
  }

  const version = markdown.match(/\*\*Version\*\*: ([\d.]+)/)?.[1] ?? '';
  return {
    errors,
    data: {
      schema: 1,
      source: 'FEATURE_PIPELINE.md',
      sourceVersion: version,
      generatedAt: new Date().toISOString(),
      entries,
      steps,
    },
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { errors, data } = buildPipelineData(fs.readFileSync(SOURCE, 'utf8'));
  if (errors.length) {
    console.error('FEATURE_PIPELINE.md has problems; nothing written:\n- ' + errors.join('\n- '));
    process.exit(1);
  }
  fs.writeFileSync(OUTPUT, JSON.stringify(data, null, 2) + '\n');
  const active = data.entries.filter((e) => !e.archived).length;
  console.log(`Wrote ${path.relative(ROOT, OUTPUT)}: ${data.entries.length} entries (${active} active), ${data.steps.length} steps.`);
}
