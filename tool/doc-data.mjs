// Builds the live document pages' data from the PRD and the Master Blueprint.
//
//   node tool/doc-data.mjs prd         writes tool/doc-prd.json
//   node tool/doc-data.mjs blueprint   writes tool/doc-blueprint.json
//
// Each page reads its JSON from its database document doc/current. The project
// hook (tool/pipeline-hook.mjs) runs this after every edit of either file and
// tells the session to push the result. Change the markdown, never the JSON.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// The three live LIQo pages, in reading order: why, how, where.
export const LINKS = [
  { source: 'LIQO_PRD.md', label: 'PRD', role: 'why', url: 'https://claude.ai/artifact/BgKuNBKJBDx4jKJ5BnfXto' },
  { source: 'LIQO_MASTER_BLUEPRINT.md', label: 'Blueprint', role: 'how', url: 'https://claude.ai/artifact/TioJyWUxE2KA2VRRL9NtJ1' },
  { source: 'FEATURE_PIPELINE.md', label: 'Pipeline', role: 'where', url: 'https://claude.ai/artifact/8QeFNHg6Xhp1jSQaMsSUx1' },
];

export const DOCS = {
  prd: { source: 'LIQO_PRD.md', output: path.join(ROOT, 'tool', 'doc-prd.json') },
  blueprint: { source: 'LIQO_MASTER_BLUEPRINT.md', output: path.join(ROOT, 'tool', 'doc-blueprint.json') },
};

export function buildDocData(key) {
  const doc = DOCS[key];
  const markdown = fs.readFileSync(path.join(ROOT, doc.source), 'utf8');
  const errors = [];
  if (!/^# .+/m.test(markdown)) errors.push(`${doc.source} has no "# " title line.`);
  const bytes = Buffer.byteLength(markdown, 'utf8');
  if (bytes > 240 * 1024) errors.push(`${doc.source} is ${Math.round(bytes / 1024)} KiB; the live page holds at most 240 KiB.`);
  return {
    errors,
    output: doc.output,
    url: LINKS.find((l) => l.source === doc.source).url,
    data: {
      schema: 1,
      source: doc.source,
      title: markdown.match(/^# (.+)$/m)?.[1].trim() ?? doc.source,
      version: markdown.match(/\*\*Version\*\*: ([\d.]+)/)?.[1] ?? '',
      generatedAt: new Date().toISOString(),
      links: LINKS,
      markdown,
    },
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const keys = process.argv[2] ? [process.argv[2]] : Object.keys(DOCS);
  for (const key of keys) {
    if (!DOCS[key]) { console.error(`Unknown document "${key}". Use: ${Object.keys(DOCS).join(', ')}.`); process.exit(1); }
    const { errors, data, output } = buildDocData(key);
    if (errors.length) { console.error('Nothing written:\n- ' + errors.join('\n- ')); process.exit(1); }
    fs.writeFileSync(output, JSON.stringify(data, null, 2) + '\n');
    console.log(`Wrote ${path.relative(ROOT, output)} from ${data.source} (${Math.round(Buffer.byteLength(data.markdown) / 1024)} KiB).`);
  }
}
