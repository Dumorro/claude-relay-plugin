#!/usr/bin/env node
/**
 * Relay hook: validate-plan-on-save
 *
 * PostToolUse advisory hook. Runs after Write|Edit completes.
 * If the edited file is an N-PLAN.md, parses frontmatter and surfaces
 * warnings via systemMessage. Never blocks — pure advisory.
 *
 * Input: tool event JSON on stdin.
 * Output: JSON with optional systemMessage, always continue: true.
 */

const fs = require('fs');

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function isPlanFile(filePath) {
  return /\.planning\/phases\/[^/]+\/[^/]*-PLAN(-\d+)?\.md$/.test(filePath)
    || /\.planning\/phases\/[^/]+\/[^/]*-\d+-PLAN\.md$/.test(filePath);
}

function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};
  const fm = {};
  for (const line of match[1].split(/\r?\n/)) {
    const kv = line.match(/^([a-zA-Z_]+):\s*(.*)$/);
    if (kv) fm[kv[1]] = kv[2].trim();
  }
  return fm;
}

function main() {
  let payload;
  try {
    payload = JSON.parse(readStdin() || '{}');
  } catch {
    return emit({});
  }

  const filePath =
    payload?.tool_response?.filePath ||
    payload?.tool_input?.file_path ||
    '';

  if (!isPlanFile(filePath)) return emit({});
  if (!fs.existsSync(filePath)) return emit({});

  const content = fs.readFileSync(filePath, 'utf8');
  const fm = parseFrontmatter(content);

  const warnings = [];
  if (!fm.approved_by || fm.approved_by === '') {
    warnings.push(
      `⚠️  Relay: ${filePath.split('/').pop()} has no \`approved_by\`. ` +
      'Fill it in before running `/relay-seal-phase`.'
    );
  }
  if (fm.plan_check && fm.plan_check !== 'PASSED') {
    warnings.push(
      `⚠️  Relay: plan_check is "${fm.plan_check}" — expected PASSED.`
    );
  }

  if (warnings.length === 0) return emit({});

  emit({ systemMessage: warnings.join('\n') });
}

function emit(obj) {
  process.stdout.write(JSON.stringify({ continue: true, suppressOutput: true, ...obj }));
}

main();
