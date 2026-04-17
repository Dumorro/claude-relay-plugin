# Troubleshooting

## `git worktree add` fails with `error: reset died of signal 10`

**Symptom:**
```
Preparing worktree (new branch 'gsd/phase-N-exec')
error: reset died of signal 10
```

**Cause:** bug in **Apple Git 2.39.5** (shipped with macOS Command Line Tools). The `pack-objects` and `reset` subprocesses crash with SIGBUS — likely mmap + APFS / Time Machine interaction.

**Fix:** install a newer git via Homebrew.

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

**Confirmed in:** pwa + core-api pilots of this workflow (2026-04-17).

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
