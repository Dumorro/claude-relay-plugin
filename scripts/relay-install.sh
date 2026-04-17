#!/usr/bin/env bash
# relay-install.sh — Install the Relay workflow into a target repo.
#
# Usage:
#   relay-install.sh <target-repo-path>
#
# Idempotent. Re-run to upgrade wrappers to the plugin's latest version.
#
# Side effects in <target>:
#   - <target>/.claude/commands/relay-*.md (copied from plugin skills)
#   - <target>/.planning/config.json  (workflow.two_profile block injected if missing)
#   - <target>/.planning/ROADMAP.md   (Lifecycle column added if missing)
#   - <target>/.gitignore             (entry for <repo-name>-exec-*/ added if missing)

set -euo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <target-repo-path>" >&2
  exit 1
fi

if [[ ! -d "$TARGET/.git" ]]; then
  echo "ABORT: $TARGET is not a git repo." >&2
  exit 1
fi

if [[ ! -d "$TARGET/.planning" ]]; then
  echo "ABORT: $TARGET has no .planning/ directory. GSD workflow expected." >&2
  exit 1
fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_NAME="$(basename "$(cd "$TARGET" && pwd)")"

echo "📦 Relay install → $TARGET (repo: $REPO_NAME)"

# 1. Copy/update wrappers as slash commands
mkdir -p "$TARGET/.claude/commands"
for skill in relay-refine-phase relay-seal-phase relay-claim-phase; do
  src="$PLUGIN_ROOT/skills/$skill/SKILL.md"
  dst="$TARGET/.claude/commands/$skill.md"
  if [[ -f "$dst" ]]; then
    if ! cmp -s "$src" "$dst"; then
      echo "  ↻  $dst (updating)"
      cp "$src" "$dst"
    else
      echo "  =  $dst (already up to date)"
    fi
  else
    echo "  +  $dst"
    cp "$src" "$dst"
  fi
done

# 2. Inject workflow.two_profile into .planning/config.json (if missing)
CONFIG="$TARGET/.planning/config.json"
if [[ -f "$CONFIG" ]] && grep -q '"two_profile"' "$CONFIG"; then
  echo "  =  $CONFIG two-profile already configured"
else
  echo "  +  $CONFIG injecting workflow.two_profile block"
  TMP="$(mktemp)"
  if command -v jq >/dev/null 2>&1; then
    jq '.workflow = (.workflow // {}) + {
          two_profile: true,
          seal_gate_required: true,
          max_parallel_executors: 3,
          architect_buffer_phases: 2
        }' "$CONFIG" > "$TMP" && mv "$TMP" "$CONFIG"
  else
    echo "  ⚠  jq not installed — edit $CONFIG manually to add workflow.two_profile block" >&2
  fi
fi

# 3. Add Lifecycle column header to ROADMAP.md (if missing)
ROADMAP="$TARGET/.planning/ROADMAP.md"
if [[ -f "$ROADMAP" ]] && ! grep -q "Two-Profile Lifecycle Status" "$ROADMAP"; then
  echo "  +  $ROADMAP (adding Lifecycle column pointer)"
  cat >> "$ROADMAP" << 'EOF'

<!-- Relay Two-Profile Lifecycle Status
Add a "Lifecycle" column to your progress table with values:
  backlog → refining → ready-for-execution → executing → verifying → done
See docs/engineering/processes/two-profile-workflow.md (or the Relay plugin docs).
-->
EOF
else
  echo "  =  $ROADMAP Lifecycle already documented or not present"
fi

# 4. Add <repo>-exec-*/ to .gitignore (if missing)
GITIGNORE="$TARGET/.gitignore"
EXEC_PATTERN="../${REPO_NAME}-exec-*/"
if [[ -f "$GITIGNORE" ]] && grep -Fq "$EXEC_PATTERN" "$GITIGNORE"; then
  echo "  =  $GITIGNORE already ignores ${REPO_NAME}-exec-*"
else
  echo "  +  $GITIGNORE adding ${REPO_NAME}-exec-*/ pattern"
  { echo ""; echo "# Relay executor worktrees"; echo "$EXEC_PATTERN"; } >> "$GITIGNORE"
fi

echo ""
echo "✅ Relay installed in $TARGET"
echo ""
echo "Next steps:"
echo "  cd $TARGET"
echo "  claude"
echo "  /relay-refine-phase <N>"
