# Config reference

## `.planning/config.json` → `workflow` block

Injected by `relay-install.sh`. Read by the seal/claim wrappers.

```json
{
  "workflow": {
    "two_profile": true,
    "seal_gate_required": true,
    "max_parallel_executors": 3,
    "architect_buffer_phases": 2
  }
}
```

### `two_profile: boolean`
Master flag. When `true`, the wrappers operate. When `false`, they abort with "two_profile disabled for this repo — enable in `.planning/config.json`."

### `seal_gate_required: boolean`
If `true` (default), `/relay-seal-phase` refuses to proceed on any failing check. If `false`, the seal emits warnings but always succeeds. Turn off only for emergency hotfixes, and restore afterwards.

### `max_parallel_executors: number` (default 3)
Upper bound on concurrent `<repo>-exec-*` worktrees. `/relay-claim-phase` warns at the limit and asks for confirmation.

### `architect_buffer_phases: number` (default 2)
Informational. How many phases ahead of the last claimed one the architect may have refined. Not enforced; used for sanity checks.

## `.planning/ROADMAP.md` → Lifecycle column

Extra column added to the progress table:

| Phase | Milestone | Plans Complete | Status | **Lifecycle** | Completed |

Valid values:
- `backlog` — not started.
- `refining` — architect is building artifacts.
- `ready-for-execution` — tag `phase-N-refined` exists.
- `executing` — executor has claimed the worktree.
- `verifying` — executor is running `/gsd-verify-work` or PR is open.
- `done` — merged.

The wrappers update this column automatically at seal (→ `ready-for-execution`) and at claim (→ `executing` if your install so chooses — v1.0 leaves this manual).

## `.planning/HANDOFF.<phase>.json` (per-phase)

Written by `/relay-seal-phase N`.

```json
{
  "version": "1.0",
  "phase": "15",
  "phase_name": "role-specific-steps",
  "phase_dir": ".planning/phases/15-role-specific-steps",
  "status": "ready-for-execution",
  "sealed_at": "2026-04-17T12:15:00Z",
  "sealed_by": "architect",
  "worktree_claimed_by": null,
  "gate_checks": {
    "context": true,
    "research": true,
    "patterns": true,
    "plan_approved": true,
    "ui_spec": true,
    "ai_spec": "n/a"
  },
  "decisions": [
    { "decision": "...", "rationale": "...", "phase": "15" }
  ],
  "notes": "Optional free text."
}
```

`/relay-claim-phase N` updates `worktree_claimed_by` and `claimed_at` on the exec branch (not on main).

Why `HANDOFF.<phase>.json` instead of a single `HANDOFF.json`? To preserve parallel work. See [ARCHITECTURE.md §per-phase HANDOFF](ARCHITECTURE.md#the-per-phase-handoff-pattern).

## `PLAN.md` frontmatter (read by gate-validator)

```yaml
---
phase: 15
title: Role-Specific Steps
gathered_at: 2026-04-07
approved_by: it@pibapp.com.br     # required for seal
approved_at: 2026-04-17
plan_check: PASSED                # from gsd-plan-checker
scope: standard                   # 'standard' | 'no-op' | 'hotfix'
---
```

- `approved_by` — **required non-empty** for seal.
- `plan_check: PASSED` — expected; other values trigger warning but don't block.
- `scope: no-op` — relaxes `gate-validator`'s CONTEXT↔PLAN mapping check.

## Git tags

One per sealed phase, annotated:

```bash
git tag -a phase-N-refined -m "Phase N refinement sealed. Ready for executor claim."
```

Tag naming is fixed: `phase-<N>-refined`. Decimal phases allowed: `phase-999.1-refined`.

## Git branches

Executor branches follow `gsd/phase-<N>-exec`. Created by `/relay-claim-phase` from the tag.

Pattern is chosen to be compatible with the `gsd/phase-*-*` templates in `.planning/config.json.git` if you already use GSD branch templates.

## Worktree naming

`<repo-name>-exec-<N>` at the sibling level of the repo.

Given `<repo-root>` = `/Users/you/repos/my-app`:
- Main worktree: `/Users/you/repos/my-app`
- Exec worktree for phase 15: `/Users/you/repos/my-app-exec-15`

Detected via `basename $(pwd)` in the claim wrapper.

## Settings: the marketplace entry

See [SETUP.md](SETUP.md#2-register-the-marketplace) for the user/workspace settings block. Key names:

- `extraKnownMarketplaces.<id>.source` — `{ "source": "file", "path": "..." }` or `{ "source": "github", "repo": "..." }`.
- `enabledPlugins["claude-relay-plugin@<marketplace-id>"]: true`.
