# Changelog

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
