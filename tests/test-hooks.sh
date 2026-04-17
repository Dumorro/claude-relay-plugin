#!/usr/bin/env bash
# Smoke test: pipe-test the hooks with synthetic payloads.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$PLUGIN_ROOT/tests/tmp/hooks-$(date +%s)"
mkdir -p "$TMP/.planning/phases/99-foo"
cat > "$TMP/.planning/phases/99-foo/99-PLAN.md" << 'EOF'
---
phase: 99
approved_by:
---

# test
EOF

FAIL=0

echo "→ Test 1: validate-plan-on-save emits warning when approved_by empty"
PAYLOAD='{"tool_input":{"file_path":"'"$TMP"'/.planning/phases/99-foo/99-PLAN.md"}}'
OUT=$(echo "$PAYLOAD" | node "$PLUGIN_ROOT/hooks/validate-plan-on-save.js")
if echo "$OUT" | grep -q "approved_by"; then
  echo "  [PASS] warning emitted"
else
  echo "  [FAIL] expected warning, got: $OUT"; FAIL=1
fi

echo ""
echo "→ Test 2: block-sealed-edits allows when no tag"
cd "$TMP" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "init"
PAYLOAD='{"tool_input":{"file_path":"'"$TMP"'/.planning/phases/99-foo/99-PLAN.md"}}'
OUT=$(echo "$PAYLOAD" | node "$PLUGIN_ROOT/hooks/block-sealed-edits.js")
if echo "$OUT" | grep -q '"permissionDecision":"allow"'; then
  echo "  [PASS] allow when no tag"
else
  echo "  [FAIL] expected allow, got: $OUT"; FAIL=1
fi

echo ""
echo "→ Test 3: block-sealed-edits asks when tag exists"
cd "$TMP" && git tag -a phase-99-refined -m "test"
OUT=$(echo "$PAYLOAD" | node "$PLUGIN_ROOT/hooks/block-sealed-edits.js")
if echo "$OUT" | grep -q '"permissionDecision":"ask"'; then
  echo "  [PASS] ask when tag exists"
else
  echo "  [FAIL] expected ask, got: $OUT"; FAIL=1
fi

rm -rf "$TMP"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "✅ test-hooks.sh: all 3 tests passed"
  exit 0
else
  echo "❌ test-hooks.sh: $FAIL failed test(s)"
  exit 1
fi
