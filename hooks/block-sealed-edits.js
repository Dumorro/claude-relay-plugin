#!/usr/bin/env node
/**
 * Relay hook: block-sealed-edits
 *
 * PreToolUse soft-block for Write|Edit. If the target file lives in a
 * sealed phase's artifact dir (.planning/phases/N-XXX) AND the local tag
 * `phase-N-refined` exists AND cwd is NOT an executor worktree
 * (<repo>-exec-N), ask the user to confirm the edit.
 *
 * Intent: prevent architects from silently mutating artifacts of a phase
 * that was handed off to an executor. Explicit confirmation unseals it.
 *
 * Input: tool event JSON on stdin.
 * Output: hookSpecificOutput.permissionDecision ("allow" | "ask").
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function findPhaseNumber(filePath) {
  const m = filePath.match(/\.planning\/phases\/([\d.]+)[-/]/);
  return m ? m[1] : null;
}

function findRepoRoot(filePath) {
  let dir = path.dirname(path.resolve(filePath));
  for (let i = 0; i < 20; i++) {
    if (fs.existsSync(path.join(dir, '.git'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function isExecWorktree(repoRoot) {
  return /-exec-[\d.]+(?:$|\/)/.test(repoRoot);
}

function tagExists(repoRoot, phase) {
  try {
    const out = execSync(`git -C "${repoRoot}" tag -l phase-${phase}-refined`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.trim() === `phase-${phase}-refined`;
  } catch {
    return false;
  }
}

function main() {
  let payload;
  try {
    payload = JSON.parse(readStdin() || '{}');
  } catch {
    return emit('allow');
  }

  const filePath = payload?.tool_input?.file_path || '';
  if (!filePath.includes('.planning/phases/')) return emit('allow');

  const phase = findPhaseNumber(filePath);
  if (!phase) return emit('allow');

  const repoRoot = findRepoRoot(filePath);
  if (!repoRoot) return emit('allow');
  if (isExecWorktree(repoRoot)) return emit('allow');
  if (!tagExists(repoRoot, phase)) return emit('allow');

  emit(
    'ask',
    `Phase ${phase} is sealed (tag phase-${phase}-refined exists). ` +
      `Editing a sealed artifact breaks the executor contract. ` +
      `If intended, confirm — or delete the tag (\`git tag -d phase-${phase}-refined\`) ` +
      `to re-open refinement, or edit inside the executor worktree.`
  );
}

function emit(decision, reason) {
  const out = {
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: decision,
    },
  };
  if (reason) out.hookSpecificOutput.permissionDecisionReason = reason;
  process.stdout.write(JSON.stringify(out));
}

main();
