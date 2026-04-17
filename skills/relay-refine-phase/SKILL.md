---
name: relay-refine-phase
description: Orchestrates the full refinement pipeline for a phase — discuss → research → pattern-map → (ui/ai if applicable) → plan. Auto-detects the repo from cwd. Architect side of the Two-Profile workflow.
argument-hint: "<phase-number>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Skill
  - Agent
---

# /relay-refine-phase — Architect refinement orchestrator

Chains the refinement pipeline for a phase in the current repo. Pauses after each artifact for human review before proceeding.

**Profile:** Architect (main worktree of the repo, default branch).
**Scope:** current repo (detected via cwd).
**Postcondition:** all gate artifacts exist in `.planning/phases/N-*/`, ready for `/relay-seal-phase N`.

---

## Arguments

`$ARGUMENTS` — phase number (e.g. `15`, `32`, `999.1`).

If empty, ask: "Which phase number do you want to refine?"

---

## Steps

You are the **Architect profile**. Execute in order from the current cwd. Do not try to change directory or touch other repos.

### 0. Initial context

- Confirm `.planning/ROADMAP.md` exists in cwd. If not, abort: "This command must run from the root of a repo with `.planning/` (e.g. `src/pwa`, `src/core-api`, `src/infra`)."
- Read `.planning/ROADMAP.md` to extract the phase goal, dependencies, requirements, success criteria.
- Read `.planning/HANDOFF.json` if present. Also check `.planning/HANDOFF.<phase>.json` — if it exists, use that instead for this phase (per-phase HANDOFF preserves parallel work).
- Detect repo name: `REPO=$(basename $(pwd))`.
- Report to the user: "Refining Phase N in `<REPO>`. Goal: <...>. Starting with `/gsd-discuss-phase`."

### 1. Discuss

Invoke `/gsd-discuss-phase N` (via Skill tool).

After completion, verify that `.planning/phases/N-*/N-CONTEXT.md` and `N-DISCUSSION-LOG.md` were generated. Ask the user to review the CONTEXT. Pause here for edits.

### 2. Research

Invoke `/gsd-research-phase N`.

Verify `.planning/phases/N-*/N-RESEARCH.md` exists with "Standard Stack" and "Pitfalls" sections (or their Portuguese equivalents). Request review.

### 3. Pattern mapping

Spawn the subagent `gsd-pattern-mapper` to produce `.planning/phases/N-*/N-PATTERNS.md`.

If the subagent is unavailable, run `/gsd-map-codebase` focusing on files mentioned by RESEARCH.md.

Verify that each new file listed in PATTERNS has a concrete analog with a path.

### 4. UI-SPEC (conditional)

Conditional: if the phase touches UI code (check CONTEXT / RESEARCH / ROADMAP). Typically applies in a frontend repo.

Invoke `/gsd-ui-phase N`. Verify `.planning/phases/N-*/N-UI-SPEC.md`. Request review.

If not applicable, skip.

### 5. AI-SPEC (conditional)

Conditional: if the phase involves an AI module (grep for `SageMaker`, `YOLOv8`, `deepfake`, `liveness`, `AI measurement`, or similar in CONTEXT / RESEARCH).

Invoke `/gsd-ai-integration-phase N`. Verify `.planning/phases/N-*/N-AI-SPEC.md`.

If not applicable, skip.

### 6. Plan

Invoke `/gsd-plan-phase N`.

Verify that `.planning/phases/N-*/N-PLAN.md` (or `N-01-PLAN.md`, `N-02-PLAN.md`, ...) was generated and that the `gsd-plan-checker` returned PASSED.

### 7. Human approval

Show the user a summary:

```
Refinement of Phase N complete in <REPO>. Artifacts:
  - N-CONTEXT.md
  - N-RESEARCH.md
  - N-PATTERNS.md
  - N-UI-SPEC.md (if applicable)
  - N-AI-SPEC.md (if applicable)
  - N-PLAN.md

Next steps:
  1. Review N-PLAN.md.
  2. Add to frontmatter: approved_by: <your handle>
  3. Commit the artifacts.
  4. Run: /relay-seal-phase N
```

Do not commit automatically — let the user review and commit.

---

## Rules

- **Never leave the current repo.** Command is scope-local.
- **Never skip steps** of the checklist without explicit confirmation. The gate depends on every artifact.
- **Never write production code** during refinement.
- If a step fails (subagent error, missing artifact), stop and report — do not proceed to the next.
- If the user asks to skip discuss/research because "I already know what I want", offer a short-circuit: generate a minimal CONTEXT.md from their description but warn that PATTERNS / PLAN are still mandatory.
