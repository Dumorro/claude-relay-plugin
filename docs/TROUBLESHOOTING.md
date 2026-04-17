# Troubleshooting

## `git worktree add` fails with `error: reset died of signal 10`

**Symptom:**
```
Preparing worktree (new branch 'gsd/phase-N-exec')
error: reset died of signal 10
```

**Cause:** bug in **Apple Git 2.39.5** (shipped with macOS Command Line Tools). The `pack-objects` and `reset` subprocesses crash with SIGBUS — likely mmap + APFS / Time Machine interaction. Also observed with Homebrew Git 2.53 on the same machine, so upgrading git alone **may not** resolve it in all environments.

### Preferred fix — install newer Git via Homebrew

```bash
brew install git
# Verify PATH priority:
which git   # should resolve to /opt/homebrew/bin/git
git version # should be ≥ 2.45
```

If `/usr/bin/git` still wins:

```bash
# Add at the top of ~/.zshrc or ~/.bashrc:
export PATH="/opt/homebrew/bin:$PATH"
```

Reopen your shell, then retry `/relay-claim-phase`.

### Fallback — rsync + read-tree (shipped in Relay v1.1.0)

If the bug persists even after upgrading git, the **`/relay-claim-phase` skill now performs this fallback automatically** (v1.1.0+). It's documented here for manual debugging.

```bash
# From inside the main worktree (e.g., src/core-api)
REPO=$(basename $(pwd))

# 1. Clean any partial state from a failed attempt
git branch -D gsd/phase-<N>-exec 2>/dev/null || true

# 2. Create worktree WITHOUT checkout (skips the reset that crashes)
git worktree add --no-checkout -b gsd/phase-<N>-exec ../${REPO}-exec-<N> phase-<N>-refined

# 3. Populate files via rsync (bypasses pack-objects entirely)
rsync -a \
  --exclude='.git' \
  --exclude='bin/' \
  --exclude='obj/' \
  --exclude='.idea/' \
  --exclude='node_modules/' \
  --exclude='.claude/worktrees' \
  ./ ../${REPO}-exec-<N>/

# 4. Populate the index from HEAD (no pack-objects needed)
cd ../${REPO}-exec-<N>
find ../${REPO}/.git/worktrees/${REPO}-exec-<N>/ -name '*.lock' -delete 2>/dev/null
git read-tree HEAD

# Verify: working tree clean (or only expected untracked)
git status --short
```

**Why not just `git worktree add --no-checkout` + `git checkout-index -a -f`?** Tested in pilots 999.1 (pwa + core-api): `checkout-index` alone produces an **empty index** because `--no-checkout` creates a worktree with no index entries. `read-tree HEAD` is what actually populates the index from the commit tree. The rsync provides the working files.

**Caveats:**
- This workaround makes the exec worktree a first-class git citizen (branch tracks the tag base commit) but bypasses any clean `git reset` the worktree setup normally does.
- If the main worktree has uncommitted tracked changes, they will be rsync'd into the exec worktree too. Commit or stash them first.
- `git status` in the exec worktree may show 1-2 files as deleted (typical: `.planning/HANDOFF.json`) if your rsync excluded them by pattern. Manually `cp` them from main if needed.

**Confirmed working in:** Phase 44 Foundation & Safety (core-api, 2026-04-17) — 100 files populated cleanly, `git status` clean after manual `cp` of 1 excluded file.

## Slash commands don't appear

**Symptom:** `/relay-refine-phase` is not listed in `/help`.

**Checks:**

1. Plugin enabled?
   ```bash
   jq '.enabledPlugins' ~/.claude/settings.json
   jq '.enabledPlugins' /your/workspace/.claude/settings.json
   ```
2. Marketplace registered with correct path?
   ```bash
   jq '.extraKnownMarketplaces' ~/.claude/settings.json
   ```
3. Restart Claude Code — changes to `settings.json` may require reload.
4. Fallback: `relay-install.sh` also writes local copies at `.claude/commands/relay-*.md`. If the plugin doesn't load but local copies do, the commands still work.

## `relay-install.sh` says `jq not installed`

The installer falls back to leaving `.planning/config.json` unchanged. Either:

```bash
brew install jq
# then re-run relay-install.sh
```

Or edit `.planning/config.json` by hand to add:

```json
"workflow": {
  "two_profile": true,
  "seal_gate_required": true,
  "max_parallel_executors": 3,
  "architect_buffer_phases": 2
}
```

## Hook doesn't fire on save

**Symptom:** edit a PLAN.md without `approved_by`, no warning appears.

**Checks:**

1. The plugin is loaded (see "Slash commands don't appear" above).
2. The file path matches `.planning/phases/*/.*-PLAN.md`.
3. Hook has `async: true` — output may arrive slightly after the tool result.

Run the hook by hand to verify:

```bash
echo '{"tool_input":{"file_path":"/path/to/repo/.planning/phases/99-foo/99-PLAN.md"}}' \
  | node ~/Documents/Repos/claude-relay-plugin/hooks/validate-plan-on-save.js
```

Expected: JSON with `systemMessage` if `approved_by` is empty.

## `block-sealed-edits` asks every time I edit planning files

That's the point — if the phase is sealed, every edit gets a prompt. To bypass:

1. Answer "yes" to the prompt (one-shot allowance).
2. Delete the tag to re-open refinement: `git tag -d phase-N-refined`.
3. Or edit inside the executor worktree (`../<repo>-exec-N`) — the hook detects exec worktrees and allows.

## `relay-cleanup-phase.sh --hard` lost commits I wanted to keep

`--hard` does `git reset --hard` to the commit BEFORE the refine commit. It asks for confirmation first. If you confirmed and regretted:

```bash
git reflog | head -20
# Find the SHA of the commit you want back
git reset --hard <sha>
```

## `relay-verify-gate.sh` says PASS but `/relay-seal-phase` aborts

Most likely the `gate-validator` subagent caught a semantic issue that the shell script doesn't check (e.g., PATTERNS analog file doesn't exist). Read the subagent's output — it names the specific failure.

## `/relay-claim-phase` succeeds but the exec worktree is empty

**Symptom:** `git worktree add` returns without error, directory exists, but `ls` on the worktree is empty.

**Cause:** partial run of the `signal 10` bug — structure created but `git reset` inside the worktree crashed silently.

**Fix:** same as the first entry — install newer git and retry.

As a last resort, `git worktree add --no-checkout` then `git checkout-index -a -f` *may* work on some systems; in the pilots above, it did not. Don't count on it.

## Tag name collision (phase already sealed before)

**Symptom:**

```
fatal: tag 'phase-15-refined' already exists
```

**Cause:** a previous refinement cycle for Phase 15 was sealed and not cleaned up.

**Fix:** choose:

```bash
# Nuke the old seal (if you're sure):
git tag -d phase-15-refined
# Re-seal:
/relay-seal-phase 15
```

## Multiple architects refining the same phase

Not supported in v1.0. If two architects try to seal Phase N concurrently, the second one will fail at the git tag step ("tag already exists"). Coordinate via chat or branching.

---

If something isn't covered here, open an issue at https://github.com/dumorro/claude-relay-plugin/issues.
