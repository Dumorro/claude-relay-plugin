---
name: relay-claim-phase
description: Executor bootstrap. Validates that the phase was sealed, creates an isolated git worktree `../<repo>-exec-N`, installs dependencies, and commits HANDOFF in the exec branch.
argument-hint: "<phase-number>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
---

# /relay-claim-phase — Executor worktree bootstrapper

Claims a sealed phase by creating an isolated worktree in the same repo, installs dependencies, and prepares the environment for execution.

**Profile:** Executor (new Claude session; entry point in the main worktree of the repo).
**Scope:** current repo (detected via cwd).
**Prerequisite:** tag `phase-N-refined` exists (created by `/relay-seal-phase`).
**Postcondition:** worktree `../<repo>-exec-N` exists on branch `gsd/phase-N-exec`, deps installed.

---

## Arguments

`$ARGUMENTS` — phase number (e.g. `15`, `32`, `999.1`).

If empty, ask: "Which phase do you want to claim?"

---

## Steps

You are the **Executor profile**. Execute in order from the current cwd.

### 1. Validate preconditions

**1.1 Are we in the main worktree?**

```bash
pwd
git worktree list
```

cwd must be the root of the repo and correspond to the main worktree (not a `<repo>-exec-*`). Otherwise abort: "Run `/relay-claim-phase` from the main worktree of the repo."

Detect repo name: `REPO=$(basename $(pwd))`. Example: `pwa`, `core-api`, `infra`.

**1.2 Does the tag exist?**

```bash
git tag -l phase-N-refined
```

Must return `phase-N-refined`. If empty:

```
ABORT: tag phase-N-refined does not exist in this repo (<REPO>).
Phase N has not passed the refinement gate yet.
If the phase belongs to another repo, cd there. Otherwise run: /relay-seal-phase N
```

**1.3 Is the worktree still absent?**

```bash
git worktree list | grep "<REPO>-exec-N"
```

If it already exists, abort: "Worktree ../<REPO>-exec-N already exists. Work in it, or run `git worktree remove ../<REPO>-exec-N` first."

**1.4 Respects `max_parallel_executors`?**

Count active `<REPO>-exec-*` worktrees. Read `.planning/config.json` → `workflow.max_parallel_executors` (default 3). If the limit is reached, warn but allow with explicit user confirmation.

### 2. Create the worktree

**Attempt 1 — standard `git worktree add`:**

```bash
git fetch --tags
git worktree add -b gsd/phase-N-exec ../<REPO>-exec-N phase-N-refined
```

Where `<REPO>` is the value of `basename $(pwd)`.

**If this fails with `error: reset died of signal 10`** (Apple Git 2.39.5 SIGBUS in `pack-objects`, see `docs/TROUBLESHOOTING.md`): do **not** abort. Use the proven fallback below (validated in real Phase 44 execution, 2026-04-17).

**Attempt 2 — fallback (bypass pack-objects via rsync + read-tree):**

```bash
# Clean any partial state
git branch -D gsd/phase-N-exec 2>/dev/null || true

# Create worktree without checkout (skips the reset that crashes)
git worktree add --no-checkout -b gsd/phase-N-exec ../<REPO>-exec-N phase-N-refined

# Populate working tree via rsync (bypasses pack-objects entirely)
rsync -a \
  --exclude='.git' \
  --exclude='bin/' \
  --exclude='obj/' \
  --exclude='.idea/' \
  --exclude='node_modules/' \
  --exclude='.claude/worktrees' \
  ./ ../<REPO>-exec-N/

# Populate the worktree's index from HEAD (no pack-objects needed)
cd ../<REPO>-exec-N
find ../<REPO>/.git/worktrees/<REPO>-exec-N/ -name '*.lock' -delete 2>/dev/null
git read-tree HEAD
```

Verify clean: `git status --short` should be empty (or show only files that should be gitignored — e.g., `.planning/HANDOFF.json` if the main worktree had it uncommitted). Copy any missing tracked files manually if `git status` shows them as `D`.

**Why not just `checkout-index`?** Tested in pilots 999.1 (pwa + core-api): `checkout-index -a -f` alone produces an **empty index** because the worktree metadata was created by `--no-checkout`. `read-tree HEAD` is what actually populates the index.

If Attempt 2 also fails (disk full, permission error, non-signal-10 cause): report cleanly and suggest `brew install git` or running from a different shell/environment. Delete orphan branch if created.

If the command fails for another reason at Attempt 1 (branch already exists, disk full, etc.), report and offer appropriate remediation.

### 3. Install dependencies in the new worktree

Detect the stack by inspecting files in the main worktree:

- `package.json` present → `cd ../<REPO>-exec-N && npm install`
- `*.slnx` or `*.sln` present → `cd ../<REPO>-exec-N && dotnet restore`
- `*.tf` files present → `cd ../<REPO>-exec-N && terraform init` (if applicable)

Run in the background (`run_in_background: true`) and monitor completion before proceeding.

### 4. Update HANDOFF in the worktree

In the **new worktree** (not the main one), update `.planning/HANDOFF.<phase>.json`:

```json
{
  ...
  "worktree_claimed_by": "claude-exec-<ISO-timestamp>",
  "claimed_at": "<ISO-8601 now>"
}
```

Commit on branch `gsd/phase-N-exec` (not main):

```bash
cd ../<REPO>-exec-N
git add .planning/HANDOFF.<phase>.json
git commit -m "chore(phase-N): claim worktree"
```

### 5. Final report

```
✅ Phase N claimed in <REPO>.

Worktree: ../<REPO>-exec-N
Branch: gsd/phase-N-exec
Base tag: phase-N-refined
Deps installed: <yes/no, tool used>
```

Then print a **bold warning banner** — this is the single most important message:

```
╔══════════════════════════════════════════════════════════════════╗
║  ⚠️  DO NOT run /gsd-execute-phase in THIS session.              ║
║                                                                  ║
║  Phase execution MUST happen in the exec worktree, NOT main.    ║
║  Running execute here pollutes main with exec commits and        ║
║  breaks the two-profile isolation guarantee.                     ║
║                                                                  ║
║  Next steps (in a NEW terminal window):                          ║
║                                                                  ║
║    cd <ABSOLUTE PATH OF ../<REPO>-exec-N>                        ║
║    claude                                                        ║
║    /gsd-execute-phase N --wave 1                                 ║
║    /gsd-verify-work N                                            ║
║    /gsd-ship                                                     ║
║                                                                  ║
║  After PR merge, back here in main:                              ║
║    /relay-finalize-phase N                                       ║
║                                                                  ║
║  The current Claude session stays as Architect in main.          ║
╚══════════════════════════════════════════════════════════════════╝
```

Replace `<ABSOLUTE PATH OF ../<REPO>-exec-N>` with the actual absolute path (expand `..` against the main worktree's parent dir).

**IMPORTANT:** the current Claude session should stay in the main worktree (Architect profile). The actual execution happens in the new window. The `enforce-worktree-execution` PreToolUse hook (shipped with this plugin) will also block `/gsd-execute-phase N` invocations from main once a sealed phase has an active exec worktree — as a safety net.

---

## Rules

- **Never run production code from the main worktree.** The claim only prepares the ground.
- **Never skip tag validation** — it's the only gate between refinement and execution.
- If `npm install` / `dotnet restore` fails, do not abort the claim. Report the error and let the user decide (may be an environmental issue, not a process one).
- If the main worktree has uncommitted changes in files that would be copied, warn the user before proceeding.
- **Never leave the current repo.** Worktrees are always same-repo.
- On `signal 10` failure, surface the Homebrew git workaround and exit cleanly — do not attempt partial materialization.
