---
name: relay-seal-phase
description: Architect gate validator. Validates the refinement checklist for a phase, updates ROADMAP/HANDOFF, commits, and creates the git tag `phase-N-refined` that unlocks the executor.
argument-hint: "<phase-number>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
---

# /relay-seal-phase — Architect gate validator

Seals a refined phase in the current repo: validates the gate checklist, updates ROADMAP/HANDOFF, commits, and creates the git tag `phase-N-refined` that unlocks the executor.

**Profile:** Architect (main worktree of the repo).
**Scope:** current repo (detected via cwd).
**Prerequisite:** PLAN.md human-reviewed with `approved_by` filled in.
**Postcondition:** tag `phase-N-refined` exists → executor can run `/relay-claim-phase N`.

---

## Arguments

`$ARGUMENTS` — phase number (e.g. `15`, `32`, `999.1`).

If empty, ask: "Which phase do you want to seal?"

---

## Steps

You are the **Architect profile**. Execute in order from the current cwd. Stop at the first error with an actionable message.

### 1. Validate context

Confirm cwd is the root of a git repo with `.planning/`:

```bash
pwd
test -d .git && test -d .planning
git worktree list
git status --short
```

If not, abort: "This command must run from the root of a repo with `.planning/` (e.g. `src/pwa`, `src/core-api`, `src/infra`)."

Detect repo name: `basename $(pwd)`. Use for logs.

Find the phase directory: `.planning/phases/N-*/` (glob). If missing, abort.

### 2. Gate checklist (ordered; abort on first failure)

For each criterion, run the check and report PASS/FAIL. Abort seal on the first FAIL.

**2.0 Spawn `gate-validator` subagent in background**

Dispatch `gate-validator` (via Agent tool) in parallel to the checks below. It verifies deeper consistency (analogs exist in PATTERNS, decisions↔tasks mapping, reference URLs in RESEARCH). Its report feeds into the final summary.

**2.1 Working tree clean for phase artifacts**
- `git status --porcelain` for the phase dir + ROADMAP + HANDOFF should be empty (artifacts already committed by refine).
- FAIL → "Working tree has uncommitted changes. Commit refine artifacts first: `git add .planning/phases/N-* && git commit`."

**2.2 CONTEXT.md**
- File: `.planning/phases/N-*/N-CONTEXT.md` exists.
- Contains "Locked decisions" (or equivalent) section with at least one decision.
- FAIL → "Context not locked. Run `/gsd-discuss-phase N`."

**2.3 RESEARCH.md**
- File: `.planning/phases/N-*/N-RESEARCH.md` exists.
- Contains "Standard Stack" and "Pitfalls" sections (or Portuguese equivalents) with non-empty content.
- FAIL → "Research incomplete. Run `/gsd-research-phase N`."

**2.4 PATTERNS.md**
- File: `.planning/phases/N-*/N-PATTERNS.md` exists.
- At least one mapping entry (new file → existing analog with path), OR an explicit note "no new files (meta phase)".
- FAIL → "Patterns not mapped. Run `/gsd-map-codebase` or use the `gsd-pattern-mapper` subagent."

**2.5 PLAN.md approved**
- File: `.planning/phases/N-*/N-PLAN.md` (or `N-01-PLAN.md` if split) exists.
- Frontmatter has `approved_by: <name>` (non-empty).
- If `N-PLAN-CHECK.md` exists (from `gsd-plan-checker`), must indicate PASSED.
- FAIL (missing plan) → "Plan missing. Run `/gsd-plan-phase N`."
- FAIL (not approved) → "Plan exists but `approved_by` is empty. Review `N-PLAN.md`, add `approved_by: <your name>` to the frontmatter and commit."

**2.6 UI-SPEC (conditional)**
- If PLAN mentions UI code (grep for `component`, `tsx`, `page`, frontend dirs): `N-UI-SPEC.md` must exist.
- FAIL → "Phase involves UI but `N-UI-SPEC.md` is missing. Run `/gsd-ui-phase N`."

**2.7 AI-SPEC (conditional)**
- If PLAN mentions AI module or keywords (`SageMaker`, `YOLOv8`, `deepfake`, `liveness`, `AI measurement`): `N-AI-SPEC.md` must exist.
- FAIL → "Phase involves AI but `N-AI-SPEC.md` is missing. Run `/gsd-ai-integration-phase N`."

**2.8 gate-validator report**
- Collect the result from the subagent spawned at step 2.0.
- If `BLOCK` verdict: abort and print the subagent's findings.
- If `WARNINGS`: show them but continue.

Show summary when all checks pass:

```
Gate checklist for Phase N (<REPO>):
  [PASS] Working tree clean
  [PASS] CONTEXT.md
  [PASS] RESEARCH.md
  [PASS] PATTERNS.md
  [PASS] PLAN.md approved by <name>
  [PASS] UI-SPEC.md
  [N/A]  AI-SPEC.md
  [PASS] gate-validator subagent
Ready to seal.
```

### 3. Update ROADMAP.md and per-phase HANDOFF

**3.1 ROADMAP.md**

Edit the phase N row to change Lifecycle to `ready-for-execution`. If the Lifecycle column doesn't exist yet, add it (one-time migration, see `docs/CONFIG-REFERENCE.md`).

**3.2 HANDOFF.<phase>.json** (per-phase file — do NOT overwrite main HANDOFF.json)

**Important:** if `.planning/HANDOFF.json` references a DIFFERENT phase already in progress, do not touch it. Always use `HANDOFF.<phase>.json` for the phase being sealed. This lets multiple phases be in flight without losing context. (Discovery from core-api pilot, 2026-04-17.)

Write `.planning/HANDOFF.<phase>.json`:

```json
{
  "version": "1.0",
  "phase": "N",
  "phase_name": "<slug>",
  "phase_dir": ".planning/phases/N-<slug>",
  "status": "ready-for-execution",
  "sealed_at": "<ISO-8601 now>",
  "sealed_by": "architect",
  "worktree_claimed_by": null,
  "gate_checks": {
    "context": true,
    "research": true,
    "patterns": true,
    "plan_approved": true,
    "ui_spec": <true|false|"n/a">,
    "ai_spec": <true|false|"n/a">
  }
}
```

### 4. Commit and tag

```bash
git add .planning/ROADMAP.md .planning/HANDOFF.<phase>.json
git commit -m "chore(phase-N): seal refinement (two-profile gate)"
git tag -a phase-N-refined -m "Phase N refinement sealed. Ready for executor claim."
```

**Do not push automatically.** Leave push to the user (pushing crosses machine/remote repositories and has blast radius).

### 5. Final report

```
✅ Phase N sealed in <REPO>.

Tag: phase-N-refined
Branch: <current> @ <short-sha>

Next steps:
  • Optional push: git push && git push --tags
  • Executor claim in a new Claude session in the same cwd:
      cd <current repo path>
      claude
      /relay-claim-phase N
```

---

## Rules

- **Never force the seal** if a check fails. Gate integrity is the whole point of the process — bypass becomes technical debt.
- **Never push or open a PR automatically.**
- If the user insists on sealing with a failing check, offer to create a `PLAN-OVERRIDE.md` documenting why the gate was ignored, but only proceed with explicit confirmation.
- **Never leave the current repo.** If the phase seems to belong to another repo, abort and instruct the user to `cd` there.
- **Never overwrite `HANDOFF.json`** if it references a different in-progress phase. Use per-phase file.
