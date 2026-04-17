# Changelog

## [1.1.0] — 2026-04-17

First real-execution hardening release. Lessons applied from Phase 44 Foundation & Safety (core-api) — the first phase that used Relay end-to-end with actual code, not a no-op pilot.

### Added
- **Skill `/relay-finalize-phase`** — architect-side closure after PR merge. Flips `HANDOFF.<phase>.json` from `ready-for-execution` to `done`, records verification score, offers optional worktree + branch cleanup, commits, and reminds to run `/jira-sync`. Closes the gap where HANDOFF stayed in `ready-for-execution` forever and exec worktrees became orphaned.
- **Hook `enforce-worktree-execution`** (PreToolUse, matcher: `Skill`) — soft-blocks `/gsd-execute-phase`, `/gsd-verify-work`, `/gsd-ship` from running in the main worktree when a sealed phase has an active exec worktree. User can still confirm to proceed (e.g., if the exec worktree was intentionally abandoned). Counters the Phase 44 failure where executor ran in main by mistake.

### Changed
- **`/relay-claim-phase` signal-10 handling** — instead of aborting with "install newer git", now attempts a proven fallback: `git worktree add --no-checkout` + `rsync --exclude=.git` + `git read-tree HEAD`. Validated end-to-end in Phase 44 execution (100 files populated cleanly, index matched HEAD). See `docs/TROUBLESHOOTING.md` for the full sequence and caveats.
- **`/relay-claim-phase` final report** — adds a bold warning banner emphasizing that `/gsd-execute-phase` must be run from a NEW terminal window in the exec worktree, not the current (architect) session. Complements the new enforce-worktree-execution hook.

### Fixed
- Signal 10 recovery: previous advice ("do NOT try workarounds") contradicted the now-validated workaround. The skill now attempts Attempt 2 automatically.

## [1.0.0] — 2026-04-17

### Added
- Three slash commands as Skills: `/relay-refine-phase`, `/relay-seal-phase`, `/relay-claim-phase`.
- Subagent `gate-validator` invoked by `/relay-seal-phase` for parallel artifact validation.
- Hook `validate-plan-on-save` (PostToolUse, advisory) — warns when editing a `N-PLAN.md` with missing `approved_by`.
- Hook `block-sealed-edits` (PreToolUse, soft-block) — asks for confirmation before editing artifacts of a sealed phase.
- Scripts: `relay-install.sh`, `relay-sync.sh`, `relay-cleanup-phase.sh`, `relay-verify-gate.sh`.
- Smoke tests covering installer and hooks.
- Documentation: ARCHITECTURE, SETUP, CONFIG-REFERENCE, TROUBLESHOOTING.

### Gate criteria
- Mandatory: `CONTEXT.md`, `RESEARCH.md`, `PATTERNS.md`, `PLAN.md` with `approved_by`.
- Conditional: `UI-SPEC.md` (if frontend), `AI-SPEC.md` (if AI module).

### Known caveats
- Apple Git `2.39.5` may crash `git worktree add` with `signal 10 (SIGBUS)`. Workaround: `brew install git` for a newer version. See `docs/TROUBLESHOOTING.md`.
