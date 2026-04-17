# Relay — Two-Profile Workflow Plugin for Claude Code

Separate architects from executors. Ship gated work.

**Relay** is a Claude Code plugin that structures software development into two disciplined roles working in isolated git worktrees:

- **Architect** refines a phase — context, research, patterns, plan — until a human stamps `approved_by`.
- **Seal** is a git tag: `phase-N-refined`. No tag, no execution.
- **Executor** claims a sealed phase into an isolated worktree and builds it. Planning artifacts are read-only on this side.

The handoff is explicit, reviewable, and reversible. No one rediscovers architectural decisions mid-implementation.

---

## Why

Running `discuss → plan → execute → verify` in a single Claude session creates three problems:

1. **Cognitive mixing** — architecture decisions compete with implementation details in the same context window.
2. **No explicit gate** — it's easy to drift into execution before planning artifacts are complete.
3. **No parallelism** — the executor is blocked while the architect refines the next phase, and vice versa.

Relay fixes all three with one git tag and four folders.

---

## Install

```bash
# 1. Clone this repo
cd ~/Documents/Repos
git clone https://github.com/Dumorro/claude-relay-plugin.git

# 2. Register the marketplace in your user settings (~/.claude/settings.json)
#    or in the workspace root .claude/settings.json:
```

```json
{
  "extraKnownMarketplaces": {
    "relay-local": {
      "source": {
        "source": "file",
        "path": "/Users/<you>/Documents/Repos/claude-relay-plugin/.claude-plugin/marketplace.json"
      }
    }
  },
  "enabledPlugins": {
    "claude-relay-plugin@relay-local": true
  }
}
```

```bash
# 3. Install into each target repo (auto-configures config.json, ROADMAP, .gitignore)
./scripts/relay-install.sh /path/to/your/repo

# 4. Open Claude from the repo root and use the slash commands
cd /path/to/your/repo
claude
```

See [`docs/SETUP.md`](docs/SETUP.md) for a complete walkthrough.

---

## Commands

| Command | Profile | What it does |
|---|---|---|
| `/relay-refine-phase N` | Architect | Orchestrates discuss → research → pattern-map → (ui/ai) → plan |
| `/relay-seal-phase N` | Architect | Validates gate, updates ROADMAP/HANDOFF, creates tag `phase-N-refined` |
| `/relay-claim-phase N` | Executor | Creates worktree `../<repo>-exec-N`, installs deps, commits HANDOFF |

---

## What's in the box

- **3 Skills** (above) — the slash commands.
- **1 Subagent** `gate-validator` — runs in parallel with `/relay-seal-phase` for deeper consistency checks.
- **2 Hooks**:
  - `validate-plan-on-save` (PostToolUse) — advisory warnings when a PLAN is saved without `approved_by`.
  - `block-sealed-edits` (PreToolUse) — asks for confirmation before editing artifacts of a sealed phase.
- **4 Scripts**:
  - `relay-install.sh` — install into a target repo.
  - `relay-sync.sh` — re-sync multiple repos with the latest plugin version.
  - `relay-cleanup-phase.sh` — remove tag + branch + worktree (with optional `--hard` reset).
  - `relay-verify-gate.sh` — dry-run of the seal checklist.
- **Documentation** in [`docs/`](docs/).

---

## The gate

`/relay-seal-phase N` only creates the tag if **all** criteria pass:

| Criterion | File | Validation |
|---|---|---|
| Context locked | `N-CONTEXT.md` | Exists + has "Locked decisions" section |
| Research | `N-RESEARCH.md` | Exists + has Standard Stack + Pitfalls sections |
| Patterns | `N-PATTERNS.md` | Exists + new files mapped to analogs with paths |
| Plan approved | `N-PLAN.md` | Exists + frontmatter has `approved_by: <name>` |
| UI spec (if frontend) | `N-UI-SPEC.md` | Conditional on PLAN touching UI |
| AI spec (if AI work) | `N-AI-SPEC.md` | Conditional on PLAN touching AI module |

One failure aborts the seal with an actionable message. No tag, no claim.

---

## Runbook

### Architect's session

```
cd <repo-root>
claude

/relay-refine-phase 15
# Review CONTEXT, RESEARCH, PATTERNS, UI-SPEC (if applicable), PLAN as they're generated
# Add approved_by: <you> to the PLAN frontmatter
# Commit the artifacts

/relay-seal-phase 15
# Gate checklist runs; tag phase-15-refined is created
```

### Executor's session (new Claude window, same repo root)

```
cd <repo-root>
claude

/relay-claim-phase 15
# Creates ../<repo>-exec-15, runs dep install

# In a NEW Claude window, open the exec worktree:
cd ../<repo>-exec-15
claude

/gsd-execute-phase 15 --wave 1
/gsd-verify-work 15
/gsd-ship
```

### After merge, architect cleans up

```
cd <repo-root>
git worktree remove ../<repo>-exec-15
git branch -d gsd/phase-15-exec
# (Optionally delete the tag if you want to reuse the number)
```

Or use the helper:

```bash
./scripts/relay-cleanup-phase.sh 15
```

---

## Status

- **Version:** 1.0.0 (2026-04-17)
- **Validated** in two independent pilots (pwa + core-api), 7/8 checks each. The one blocked check is an environmental git bug (Apple Git 2.39.5 `signal 10`), fully documented in [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## License

MIT — see [`LICENSE`](LICENSE).
