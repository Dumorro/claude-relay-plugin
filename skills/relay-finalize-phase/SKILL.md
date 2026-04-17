---
name: relay-finalize-phase
description: Architect post-merge closure. Marks a phase as done in HANDOFF.N.json, optionally cleans up exec worktree and branch, commits, and reminds to sync Jira.
argument-hint: "<phase-number>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
---

# /relay-finalize-phase — Architect post-merge closure

Closes the Relay loop after the executor's PR has been merged. Flips `HANDOFF.<phase>.json` from `ready-for-execution` to `done`, records verification score, optionally removes the exec worktree + branch, commits the finalization, and reminds the operator to sync Jira.

**Profile:** Architect (main worktree of the repo).
**Scope:** current repo (detected via cwd).
**Prerequisite:** PR for `gsd/phase-N-exec` merged into the integration branch the executor targeted (usually `main`). `.planning/phases/N-*/*-VERIFICATION.md` must exist with `status: passed`.
**Postcondition:** `HANDOFF.<phase>.json` has `status: "done"`; working tree is clean; optionally the exec worktree and branch are removed.

---

## Arguments

`$ARGUMENTS` — phase number (e.g. `15`, `32`, `44`).

If empty, ask: "Which phase do you want to finalize?"

---

## Steps

You are the **Architect profile**. Execute in order from the main worktree of the repo.

### 1. Validate preconditions

**1.1 Are we in the main worktree?**

```bash
pwd
git worktree list
```

cwd must be the main worktree of the repo (not a `<repo>-exec-*`). Otherwise abort: "Run `/relay-finalize-phase` from the main worktree."

**1.2 Find the VERIFICATION report and score**

Glob for `.planning/phases/<phase>-*/*-VERIFICATION.md`. There should be exactly one. Read the frontmatter:

```yaml
---
phase: <phase>-*
verified: <ISO timestamp>
status: passed
score: <X/Y>
---
```

If `status` is not `passed` — abort with: "VERIFICATION.md reports status=<status>, not passed. Re-run /gsd-verify-work in the executor worktree until passed before finalizing."

If the file does not exist — abort with: "No VERIFICATION.md for phase <phase>. The executor must run /gsd-verify-work first."

**1.3 Detect Jira subtasks (best-effort)**

Glob for `.planning/phases/<phase>-*/<phase>-*-PLAN.md` to list all plans (including gap-closure plans added post-seal). Cross-reference with `data/jira-mapping.json` (if present at workspace root) to collect Jira keys for reporting purposes.

This is informational — do not fail if mapping is absent.

### 2. Read current HANDOFF.<phase>.json

Expected schema (produced by `/relay-seal-phase`):

```json
{
  "version": "1.0",
  "phase": "<phase>",
  "status": "ready-for-execution",
  ...
}
```

If status is already `done`, ask the user: "Phase <phase> is already finalized (HANDOFF.<phase>.json status=done). Re-finalize anyway? (y/n)".

### 3. Update HANDOFF.<phase>.json

Rewrite with:

```json
{
  "version": "1.0",
  "phase": "<phase>",
  "phase_name": "<from original>",
  "status": "done",
  "sealed_at": "<original>",
  "sealed_by": "<original>",
  "worktree_claimed_by": "<from exec branch if available>",
  "claimed_at": "<original or now>",
  "verified_at": "<from VERIFICATION frontmatter>",
  "score": "<X/Y>",
  "plans": ["<all plan IDs discovered in step 1.3>"],
  "waves": { <preserve original> },
  "gate_checks": { <preserve original> },
  "jira": {
    "epic": "<from mapping if known>",
    "feature": "<from mapping if known>",
    "subtasks": ["<list from mapping>"]
  },
  "finalized_at": "<now ISO>",
  "finalized_via": "relay-finalize-phase"
}
```

Preserve every field from the pre-existing HANDOFF that this skill does not explicitly overwrite.

### 4. Optional worktree + branch cleanup

**4.1 Worktree:**

```bash
REPO=$(basename $(pwd))
git worktree list | grep "${REPO}-exec-<phase>"
```

If the exec worktree still exists, ask the user:

> Exec worktree `../${REPO}-exec-<phase>` still exists. Remove it? (y/n)
>
> Choose `n` if you want to keep it for debugging. Choose `y` to remove cleanly.

If `y`:

```bash
git worktree remove "../${REPO}-exec-<phase>"
```

If removal fails because of uncommitted changes in the exec worktree, report and abort this step (do not force).

**4.2 Branch:**

```bash
git branch --list gsd/phase-<phase>-exec
```

If the branch still exists locally AND it has been merged (`git branch --merged main` includes it), ask:

> Branch `gsd/phase-<phase>-exec` is merged. Delete it? (y/n)

If `y`:

```bash
git branch -d gsd/phase-<phase>-exec
```

If the branch is not merged (e.g., the executor pushed their own branch and you merged via PR squash), `git branch -d` will refuse — in that case recommend `git branch -D` with confirmation but do not run it automatically.

### 5. Commit finalization

```bash
git add .planning/HANDOFF.<phase>.json
git commit -m "chore(phase-<phase>): mark as done (Relay finalization)"
```

Do **not** push automatically — the architect decides when to push the finalization.

### 6. Final report

```
✅ Phase <phase> finalized.

HANDOFF.<phase>.json:
  status: done
  verified_at: <timestamp>
  score: <X/Y>
  plans: <count>

Worktree:    <removed | kept at ../REPO-exec-N>
Branch:      <deleted | kept | not merged>
Commit:      <SHA> (unpushed)

Next steps:
  1. Push the finalization commit:
       git push origin main
  2. Sync Jira (if using claude-gsd-jira-plugin):
       /jira-sync
     This will transition Feature + all its subtasks to Concluído.
  3. Roll to the next phase:
       /relay-refine-phase <N+1>
```

---

## Rules

- **Do not run** this from an exec worktree — it operates on main artifacts.
- **Do not force** branch deletion (`-D`) automatically — require explicit user confirmation for unmerged branches.
- **Do not mutate** sealed phase artifacts (CONTEXT/RESEARCH/PATTERNS/PLAN/UI-SPEC/AI-SPEC) — they stay as historical record.
- **Do not push** the commit — that's the architect's decision (some teams batch pushes).
- **Do not assume** the exec worktree still exists or the branch still exists — some workflows clean up during `/gsd-ship`. Skip those steps gracefully.
- If the PR was merged via squash or rebase, the local `gsd/phase-N-exec` branch may not show as merged. Require explicit confirmation before `-D`.

---

## Relationship to other skills

| Skill | When | Does |
|---|---|---|
| `/relay-refine-phase` | Pre-seal | Orchestrates discuss→research→pattern→(ui/ai)→plan |
| `/relay-seal-phase` | After human approval | Gate 7/7 → tag `phase-N-refined` |
| `/relay-claim-phase` | Executor bootstrap | Creates exec worktree + deps |
| `/gsd-execute-phase` | In exec worktree | Runs plans by wave |
| `/gsd-verify-work` | In exec worktree | Conversational UAT → VERIFICATION.md |
| `/gsd-ship` | In exec worktree | Opens PR |
| **`/relay-finalize-phase`** | **Back in main after PR merge** | **Closes HANDOFF + cleanup + sync reminder** |

This skill is **new in Relay v1.1.0** — it closes a gap observed in Phase 44 where HANDOFF.N.json stayed in `ready-for-execution` forever even after the phase was verified and merged, and the exec worktree + branch became orphaned.
