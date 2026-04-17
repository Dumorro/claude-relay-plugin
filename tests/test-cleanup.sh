#!/usr/bin/env bash
# Smoke test: relay-cleanup-phase.sh behavior with tag + branch.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$PLUGIN_ROOT/tests/tmp/cleanup-$(date +%s)"
mkdir -p "$TMP"
cd "$TMP" && git init -q && echo x > a && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init"

# Create mock refined phase
git tag -a phase-99-refined -m "test"
git branch gsd/phase-99-exec

FAIL=0

echo "→ Running relay-cleanup-phase.sh 99 (soft mode)"
"$PLUGIN_ROOT/scripts/relay-cleanup-phase.sh" 99

echo ""
echo "--- Assertions ---"
if [[ -z "$(git tag -l phase-99-refined)" ]]; then
  echo "  [PASS] tag removed"
else
  echo "  [FAIL] tag still exists"; FAIL=1
fi
if ! git branch --list "gsd/phase-99-exec" | grep -q .; then
  echo "  [PASS] branch removed"
else
  echo "  [FAIL] branch still exists"; FAIL=1
fi

rm -rf "$TMP"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "✅ test-cleanup.sh: all assertions passed"
  exit 0
else
  echo "❌ test-cleanup.sh: $FAIL failed"
  exit 1
fi
