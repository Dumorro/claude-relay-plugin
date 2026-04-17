# Setup

Step-by-step installation for the Relay plugin.

## Prerequisites

- **Claude Code** ≥ 2.0.
- **git** ≥ 2.30 (Apple Git 2.39.5 has a known SIGBUS bug on `git worktree add` — see [TROUBLESHOOTING](TROUBLESHOOTING.md)).
- **Node.js** ≥ 18 (for hooks; only stdlib is used, no `npm install` needed).
- Target repo has a `.planning/` directory following the GSD layout.

Optional but recommended:
- **jq** (for `.planning/config.json` edits during install).

## 1. Clone the plugin

```bash
cd ~/Documents/Repos
git clone https://github.com/Dumorro/claude-relay-plugin.git
cd claude-relay-plugin
```

## 2. Register the marketplace

Add to `~/.claude/settings.json` (global) or to your workspace root `.claude/settings.json`. Two options:

### Option A — local file (dev / offline / personal use)

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

### Option B — GitHub (shared / versioned install)

```json
{
  "extraKnownMarketplaces": {
    "relay-github": {
      "source": {
        "source": "github",
        "repo": "Dumorro/claude-relay-plugin",
        "ref": "v1.0.0"
      }
    }
  },
  "enabledPlugins": {
    "claude-relay-plugin@relay-github": true
  }
}
```

Use a specific tag (e.g. `v1.0.0`) or `main` for rolling updates. Claude Code clones the repo under `~/.claude/plugins/cache/` and refreshes per the `autoUpdate` flag.

Restart Claude Code (or run `/plugins` to reload).

## 3. Verify the plugin loaded

In a new Claude session:

```
/help
```

You should see `/relay-refine-phase`, `/relay-seal-phase`, `/relay-claim-phase` listed. If not, check the marketplace source path and the plugin name match.

## 4. Install into a target repo

```bash
cd ~/Documents/Repos/claude-relay-plugin
./scripts/relay-install.sh /path/to/your/repo
```

The installer is idempotent. It:

- Copies the 3 Skills to `<target>/.claude/commands/relay-*.md` (local fallback — useful if the plugin is unloaded).
- Injects `workflow.two_profile` block into `<target>/.planning/config.json` (requires `jq`).
- Adds a Lifecycle column pointer to `<target>/.planning/ROADMAP.md`.
- Adds `../<repo>-exec-*/` to `<target>/.gitignore`.

Re-run to propagate plugin updates.

## 5. Sync multiple repos at once

```bash
./scripts/relay-sync.sh \
  /path/to/repo-a \
  /path/to/repo-b \
  /path/to/repo-c
```

## 6. First phase

From the target repo root:

```bash
cd /path/to/your/repo
claude
```

In the Claude session:

```
/relay-refine-phase 15
# Review each artifact as it's generated
# Add `approved_by: <your handle>` to N-PLAN.md
# Commit the artifacts

/relay-seal-phase 15
# Gate runs. On success, tag `phase-15-refined` is created.

/relay-claim-phase 15
# Worktree ../<repo>-exec-15 is created and deps installed.
```

Then open a second Claude window inside the exec worktree to run the executor pipeline.

## 7. Verify the gate without sealing (dry-run)

```bash
cd /path/to/your/repo
~/Documents/Repos/claude-relay-plugin/scripts/relay-verify-gate.sh 15
```

Prints PASS/FAIL per check. Exit code 0 if ready to seal.

## Upgrading

When the plugin repo gets new commits:

```bash
cd ~/Documents/Repos/claude-relay-plugin
git pull

# Re-sync your target repos
./scripts/relay-sync.sh /path/to/repo-a /path/to/repo-b ...
```

## Uninstalling

To disable but keep files:

```json
"enabledPlugins": { "claude-relay-plugin@relay-local": false }
```

To fully remove from a target repo:

```bash
rm /path/to/repo/.claude/commands/relay-*.md
# Remove the workflow.two_profile block from .planning/config.json manually
# (optional) remove the Lifecycle column / pointer from ROADMAP
# Remove the ignored `-exec-*` pattern from .gitignore if unwanted
```
