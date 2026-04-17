# Architecture

## The Two-Profile model

```
┌──────────────────────────────────────────────────────────────┐
│                       ARCHITECT                              │
│                (main worktree, default branch)               │
│                                                              │
│   /relay-refine-phase N                                      │
│       ├─ /gsd-discuss-phase   → N-CONTEXT.md                 │
│       ├─ /gsd-research-phase  → N-RESEARCH.md                │
│       ├─ pattern-mapper       → N-PATTERNS.md                │
│       ├─ /gsd-ui-phase   (if) → N-UI-SPEC.md                 │
│       ├─ /gsd-ai-phase   (if) → N-AI-SPEC.md                 │
│       └─ /gsd-plan-phase      → N-PLAN.md (+ gsd-plan-checker)│
│                                                              │
│   Human adds: approved_by: <name> to PLAN frontmatter        │
│   Commit the artifacts                                       │
│                                                              │
│   /relay-seal-phase N                                        │
│       ├─ Checklist (gate-validator subagent in parallel)     │
│       ├─ Update ROADMAP.md (Lifecycle = ready-for-execution) │
│       ├─ Write HANDOFF.<phase>.json                          │
│       ├─ Commit                                              │
│       └─ git tag -a phase-N-refined                          │
└──────────────────────────────────────────────────────────────┘
                              │
                              │  tag phase-N-refined
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                       EXECUTOR                               │
│         (isolated worktree ../<repo>-exec-N,                 │
│          branch gsd/phase-N-exec)                            │
│                                                              │
│   /relay-claim-phase N                                       │
│       ├─ Validate tag exists                                 │
│       ├─ git worktree add -b gsd/phase-N-exec ../<repo>-exec-N│
│       ├─ Install deps (npm / dotnet restore / terraform init)│
│       └─ Commit HANDOFF update on exec branch                │
│                                                              │
│   In new Claude window in ../<repo>-exec-N:                  │
│       /gsd-execute-phase N --wave 1                          │
│       /gsd-verify-work N                                     │
│       /gsd-ship  → PR                                        │
└──────────────────────────────────────────────────────────────┘
                              │
                              │  PR
                              ▼
                     Architect merges in main
                              │
                              ▼
           git worktree remove + branch -d + (optional tag -d)
```

## Why a git tag

Because:

- **Immutable** — tag points to a specific commit that includes all the gate artifacts. No "PR description changed behind your back."
- **Atomic with the code** — refinement lives in the same repo as the code being refined. No external tracker to sync.
- **Reversible** — delete the tag and the gate re-opens.
- **Queryable** — `git tag -l phase-*-refined` gives you a dashboard of what's ready.
- **Free** — no new infrastructure.

## Why a separate worktree

Because:

- **Isolation** — executor can't accidentally mutate planning artifacts, and architect can't accidentally compile.
- **Parallelism** — up to `max_parallel_executors` (default 3) phases can be mid-execution simultaneously, each in its own worktree.
- **Clean rollback** — `git worktree remove` wipes all partial work without touching the main tree.
- **Same repo** — worktrees share `.git/objects`, so disk cost is mainly the checkout (~300-500MB per phase depending on stack).

## What the hooks do

### `validate-plan-on-save.js` (PostToolUse, advisory)

Triggers on any Write/Edit. If the edited file is a `N-PLAN.md`, parses its frontmatter:
- If `approved_by` is empty, emits a warning system message.
- If `plan_check` is set to anything other than `PASSED`, warns.

Never blocks. It's a nudge.

### `block-sealed-edits.js` (PreToolUse, soft-block)

Triggers before any Write/Edit. If:
1. Target path is inside `.planning/phases/N-*/`, AND
2. `git tag -l phase-N-refined` returns the tag, AND
3. cwd is NOT an executor worktree (`<repo>-exec-*`)

...then returns `permissionDecision: "ask"` with a reason explaining that a sealed phase's artifacts should not be edited in the architect worktree. User can override with confirmation.

## What `gate-validator` adds to `/relay-seal-phase`

The subagent runs in parallel with the linear checklist and catches semantic issues:

| Check | What it verifies |
|---|---|
| PATTERNS analogs exist | Every analog path in `N-PATTERNS.md` resolves on disk |
| CONTEXT ↔ PLAN mapping | Every locked decision maps to at least one task (or is explicitly meta) |
| RESEARCH references | Each Standard Stack claim has a citation (URL, file, or skill) |
| Frontmatter sanity | `approved_by`, `plan_check`, `scope` present |

Returns `PASS`, `WARN`, or `BLOCK`. `BLOCK` aborts the seal.

## The per-phase HANDOFF pattern

Earlier drafts had the seal overwrite `.planning/HANDOFF.json`. This breaks when multiple phases are in flight: the architect can be refining Phase N+1 while the executor is still working on Phase N.

**Relay writes `.planning/HANDOFF.<phase>.json`** — one file per phase. `HANDOFF.json` (if it exists) is left alone.

Discovered during the core-api pilot (2026-04-17): sealing 999.1 would have erased Phase 44's in-progress state. Per-phase handoff avoids that.

## Relationship to GSD

Relay sits on top of `gsd-*` skills. It doesn't reimplement them:
- `/relay-refine-phase` calls `/gsd-discuss-phase`, `/gsd-research-phase`, `/gsd-plan-phase`, etc.
- `/relay-claim-phase` hands off to `/gsd-execute-phase` (in a new Claude session).

If you don't use GSD, Relay as-is won't fit. Adapt the Skills to point at your own refine/execute primitives.
