#!/usr/bin/env bash
# Smoke test: relay-install.sh in a disposable fake repo.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$PLUGIN_ROOT/tests/fixtures/fake-repo"
TMP="$PLUGIN_ROOT/tests/tmp/fake-repo-install-$(date +%s)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP"
cp -R "$FIXTURE/." "$TMP/"
cd "$TMP" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init"
cd "$PLUGIN_ROOT"

echo "→ Running relay-install.sh on $TMP"
./scripts/relay-install.sh "$TMP"

FAIL=0
check_file() {
  if [[ -f "$1" ]]; then echo "  [PASS] $1 exists"; else echo "  [FAIL] $1 missing"; FAIL=1; fi
}
check_grep() {
  if grep -q "$2" "$1" 2>/dev/null; then echo "  [PASS] $1 contains '$2'"; else echo "  [FAIL] $1 missing '$2'"; FAIL=1; fi
}

echo ""
echo "--- Assertions ---"
check_file "$TMP/.claude/commands/relay-refine-phase.md"
check_file "$TMP/.claude/commands/relay-seal-phase.md"
check_file "$TMP/.claude/commands/relay-claim-phase.md"
check_grep "$TMP/.planning/config.json" "two_profile"
check_grep "$TMP/.gitignore" "exec-"
check_grep "$TMP/.planning/ROADMAP.md" "Two-Profile Lifecycle"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "✅ test-install.sh: all assertions passed"
  exit 0
else
  echo "❌ test-install.sh: $FAIL failed assertion(s)"
  exit 1
fi
