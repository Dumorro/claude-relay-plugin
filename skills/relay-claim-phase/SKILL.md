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

```bash
git fetch --tags
git worktree add -b gsd/phase-N-exec ../<REPO>-exec-N phase-N-refined
```

Where `<REPO>` is the value of `basename $(pwd)`.

**If the command fails with `error: reset died of signal 10`** (known Apple Git 2.39.5 bug, see `docs/TROUBLESHOOTING.md`):

1. Report clearly to the user: "Known Apple Git signal 10 bug detected. `git worktree add` cannot materialize the checkout."
2. Suggest: "Install newer git: `brew install git`. Then retry `/relay-claim-phase N`."
3. Do NOT try workarounds (`--no-checkout` + `checkout-index` creates an empty index — confirmed in both pwa and core-api pilots).
4. Exit gracefully — leave no partial state (delete orphan branch if created).

If the command fails for another reason (branch already exists, disk full, etc.), report and offer appropriate remediation.

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

Next step — open a NEW Claude window pointing at the worktree:
  cd <full path to ../<REPO>-exec-N>
  claude

In the new Claude session, run the executor pipeline:
  /gsd-execute-phase N --wave 1
  /gsd-verify-work N
  /gsd-ship

After merge, clean up:
  cd <full path to main worktree>
  git worktree remove ../<REPO>-exec-N
  git branch -d gsd/phase-N-exec
```

**IMPORTANT:** the current Claude session should stay in the main worktree (Architect profile). The actual execution happens in the new window.

---

## Rules

- **Never run production code from the main worktree.** The claim only prepares the ground.
- **Never skip tag validation** — it's the only gate between refinement and execution.
- If `npm install` / `dotnet restore` fails, do not abort the claim. Report the error and let the user decide (may be an environmental issue, not a process one).
- If the main worktree has uncommitted changes in files that would be copied, warn the user before proceeding.
- **Never leave the current repo.** Worktrees are always same-repo.
- On `signal 10` failure, surface the Homebrew git workaround and exit cleanly — do not attempt partial materialization.
