// PostToolUse hook (.claude/settings.json): after an edit of FEATURE_PIPELINE.md,
// LIQO_PRD.md or LIQO_MASTER_BLUEPRINT.md, rebuild that live page's data and
// tell the session to push it. Any other file: do nothing.

import fs from 'node:fs';
import path from 'node:path';
import { buildPipelineData, SOURCE, OUTPUT } from './pipeline-data.mjs';
import { buildDocData } from './doc-data.mjs';

const PIPELINE_PAGE = 'https://claude.ai/artifact/8QeFNHg6Xhp1jSQaMsSUx1';

let input = '';
for await (const chunk of process.stdin) input += chunk;

let payload = {};
try {
  payload = JSON.parse(input || '{}');
} catch {
  process.exit(0);
}
const file = path.basename(payload.tool_input?.file_path ?? payload.tool_response?.filePath ?? '').toLowerCase();

const say = (text) =>
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: text } }));

const push = (name, url, collection, json) =>
  `${name} changed; its live page data was rebuilt at ${json}. ` +
  `When you have finished editing ${name} in this turn, push it once: ` +
  `ArtifactData action "get" with url ${url}, collection "${collection}", doc_id "current" to read its version, ` +
  `then ArtifactData action "set" with the same url, collection and doc_id, file_path "${json}" and if_version set to that version. ` +
  'Then tell the user in one line that the live page is updated.';

const fail = (name, errors) =>
  `${name} changed, but its live page was NOT updated because of problems. ` +
  'Fix them, and the next edit will rebuild the page data:\n- ' + errors.join('\n- ');

if (file === 'feature_pipeline.md') {
  const { errors, data } = buildPipelineData(fs.readFileSync(SOURCE, 'utf8'));
  if (errors.length) say(fail('FEATURE_PIPELINE.md', errors));
  else {
    fs.writeFileSync(OUTPUT, JSON.stringify(data, null, 2) + '\n');
    say(push('FEATURE_PIPELINE.md', PIPELINE_PAGE, 'pipeline', OUTPUT));
  }
} else if (file === 'liqo_prd.md' || file === 'liqo_master_blueprint.md') {
  const key = file === 'liqo_prd.md' ? 'prd' : 'blueprint';
  const { errors, data, output, url } = buildDocData(key);
  if (errors.length) say(fail(data.source, errors));
  else {
    fs.writeFileSync(output, JSON.stringify(data, null, 2) + '\n');
    say(push(data.source, url, 'doc', output));
  }
}
