#!/usr/bin/env node
/**
 * Relay hook: enforce-worktree-execution
 *
 * PreToolUse guard for Skill. If the user invokes a GSD execute/verify/ship
 * skill (gsd-execute-phase, gsd-verify-work, gsd-ship) from the MAIN worktree
 * of a repo that ALSO has an active exec worktree (../<repo>-exec-<N>) for
 * that phase, block with an actionable message.
 *
 * Why: running execution skills in the main worktree defeats the two-profile
 * isolation — commits pollute main, exec worktree becomes orphaned, the
 * gsd/phase-N-exec branch is lost (real failure observed in Phase 44).
 *
 * Decision mode: "ask" (soft-block). User can confirm if they really mean to
 * run in main (e.g., the exec worktree was intentionally abandoned and needs
 * cleanup).
 *
 * Input: tool event JSON on stdin.
 * Output: hookSpecificOutput.permissionDecision ("allow" | "ask").
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const GUARDED_SKILLS = new Set([
  'gsd-execute-phase',
  'gsd-verify-work',
  'gsd-ship',
]);

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function extractSkillAndArgs(input) {
  // Claude Code's Skill tool uses `{skill, args}` in tool_input.
  const skill = (input?.skill || '').toString().trim().replace(/^\//, '');
  const args = (input?.args || '').toString();
  return { skill, args };
}

function extractPhaseNumber(args) {
  // Skills accept the phase as a positional arg, possibly with extra flags.
  // e.g. "44", "44 --wave 1", "999.1".
  const m = args.match(/(\d+(?:\.\d+)?)/);
  return m ? m[1] : null;
}

function getRepoRoot(cwd) {
  try {
    const out = execSync('git rev-parse --show-toplevel', {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.trim();
  } catch {
    return null;
  }
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

function execWorktreePath(repoRoot, phase) {
  const repoName = path.basename(repoRoot);
  const parent = path.dirname(repoRoot);
  return path.join(parent, `${repoName}-exec-${phase}`);
}

function worktreeExists(repoRoot, phase) {
  try {
    const out = execSync(`git -C "${repoRoot}" worktree list --porcelain`, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    const target = execWorktreePath(repoRoot, phase);
    return out.includes(target);
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

  const { skill, args } = extractSkillAndArgs(payload?.tool_input);
  if (!GUARDED_SKILLS.has(skill)) return emit('allow');

  const phase = extractPhaseNumber(args);
  if (!phase) return emit('allow');

  const cwd = process.cwd();
  const repoRoot = getRepoRoot(cwd);
  if (!repoRoot) return emit('allow');

  // If we're already in an exec worktree, green-light.
  if (isExecWorktree(repoRoot)) return emit('allow');

  // Only guard when the phase is actually sealed (tag exists).
  if (!tagExists(repoRoot, phase)) return emit('allow');

  // And only when the exec worktree still exists (otherwise execution on main
  // is the only option anyway — e.g., user removed exec by mistake).
  if (!worktreeExists(repoRoot, phase)) return emit('allow');

  const execPath = execWorktreePath(repoRoot, phase);
  emit(
    'ask',
    `You're about to run /${skill} ${phase} in the main worktree.\n` +
      `The exec worktree for phase ${phase} exists at:\n  ${execPath}\n\n` +
      `The two-profile workflow requires execution there (not main), or commits pollute main and the exec branch becomes orphaned (real failure observed in Phase 44).\n\n` +
      `Recommended:\n` +
      `  1) Open a new Claude session in the exec worktree:\n` +
      `     cd ${execPath} && claude\n` +
      `  2) Run /${skill} ${phase} there.\n\n` +
      `If you really mean to run in main (e.g., exec was abandoned), confirm to proceed. Consider cleanup first:\n` +
      `  git worktree remove ${execPath}\n` +
      `  git branch -D gsd/phase-${phase}-exec`
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
