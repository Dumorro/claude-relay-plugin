#!/usr/bin/env bash
# relay-verify-gate.sh — Dry-run of the seal checklist. Prints PASS/FAIL per check without sealing.
#
# Usage:
#   relay-verify-gate.sh <phase-number>
#
# Exit code 0 if all checks pass (ready to seal), 1 otherwise.

set -euo pipefail

PHASE="${1:-}"
if [[ -z "$PHASE" ]]; then
  echo "Usage: $0 <phase-number>" >&2
  exit 1
fi

if [[ ! -d ".planning" ]]; then
  echo "ABORT: .planning/ not found in cwd." >&2
  exit 1
fi

PHASE_DIR="$(find .planning/phases -maxdepth 1 -type d -name "${PHASE}-*" | head -1)"
if [[ -z "$PHASE_DIR" ]]; then
  echo "ABORT: no directory .planning/phases/${PHASE}-* found." >&2
  exit 1
fi

echo "🔎 Relay gate verify for Phase $PHASE ($PHASE_DIR)"
echo ""

FAIL=0
check() {
  local label="$1" ok="$2" msg="${3:-}"
  if [[ "$ok" == "1" ]]; then
    echo "  [PASS] $label"
  else
    echo "  [FAIL] $label $msg"
    FAIL=1
  fi
}

# Working tree clean for phase files
if [[ -z "$(git status --porcelain "$PHASE_DIR" .planning/ROADMAP.md 2>/dev/null)" ]]; then
  check "Working tree clean" 1
else
  check "Working tree clean" 0 "(uncommitted changes in phase dir or ROADMAP)"
fi

# CONTEXT
CONTEXT="$PHASE_DIR/${PHASE}-CONTEXT.md"
if [[ -f "$CONTEXT" ]] && grep -qiE "Locked decisions|Locked Decisions" "$CONTEXT"; then
  check "CONTEXT.md + Locked Decisions" 1
else
  check "CONTEXT.md + Locked Decisions" 0
fi

# RESEARCH
RESEARCH="$PHASE_DIR/${PHASE}-RESEARCH.md"
if [[ -f "$RESEARCH" ]] && grep -qi "Standard Stack" "$RESEARCH" && grep -qi "Pitfalls" "$RESEARCH"; then
  check "RESEARCH.md (Standard Stack + Pitfalls)" 1
else
  check "RESEARCH.md (Standard Stack + Pitfalls)" 0
fi

# PATTERNS
PATTERNS="$PHASE_DIR/${PHASE}-PATTERNS.md"
if [[ -f "$PATTERNS" ]]; then
  check "PATTERNS.md" 1
else
  check "PATTERNS.md" 0
fi

# PLAN + approved_by
PLAN="$(find "$PHASE_DIR" -name "${PHASE}-PLAN.md" -o -name "${PHASE}-01-PLAN.md" | head -1)"
if [[ -n "$PLAN" ]]; then
  APPROVED="$(grep -E '^approved_by:' "$PLAN" | head -1 | sed -E 's/^approved_by:[[:space:]]*//' | tr -d '\r\n')"
  if [[ -n "$APPROVED" ]]; then
    check "PLAN.md approved by $APPROVED" 1
  else
    check "PLAN.md approved_by" 0 "(empty — add 'approved_by: <you>' to frontmatter)"
  fi
else
  check "PLAN.md present" 0
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ All gate checks pass. Ready to seal:"
  echo "   /relay-seal-phase $PHASE"
  exit 0
else
  echo "❌ Gate not ready. Fix the failures above and re-run."
  exit 1
fi
