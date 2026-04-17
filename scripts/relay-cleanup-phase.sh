#!/usr/bin/env bash
# relay-cleanup-phase.sh — Remove tag + branch + worktree for a phase.
#
# Usage:
#   relay-cleanup-phase.sh <phase-number> [--hard]
#
# Default: removes tag, exec branch, and exec worktree. Refine/seal commits
# remain in history.
#
# --hard: also git reset --hard to the commit BEFORE the refine commit.
#         Destructive — requires confirmation.

set -euo pipefail

PHASE="${1:-}"
MODE="${2:-soft}"

if [[ -z "$PHASE" ]]; then
  echo "Usage: $0 <phase-number> [--hard]" >&2
  exit 1
fi

if [[ ! -d ".git" ]]; then
  echo "ABORT: run from the main worktree of a git repo." >&2
  exit 1
fi

REPO="$(basename "$(pwd)")"
TAG="phase-${PHASE}-refined"
BRANCH="gsd/phase-${PHASE}-exec"
WORKTREE="../${REPO}-exec-${PHASE}"

echo "🧹 Relay cleanup for Phase $PHASE in $REPO"
echo "  Tag:      $TAG"
echo "  Branch:   $BRANCH"
echo "  Worktree: $WORKTREE"
echo ""

# 1. Worktree
if git worktree list | grep -q "${REPO}-exec-${PHASE}"; then
  echo "  ↓  removing worktree $WORKTREE"
  git worktree remove --force "$WORKTREE" 2>/dev/null || true
else
  echo "  —  no worktree at $WORKTREE"
fi

# 2. Branch
if git branch --list "$BRANCH" | grep -q .; then
  echo "  ↓  deleting branch $BRANCH"
  git branch -D "$BRANCH"
else
  echo "  —  no branch $BRANCH"
fi

# 3. Tag
if [[ -n "$(git tag -l "$TAG")" ]]; then
  echo "  ↓  deleting tag $TAG"
  git tag -d "$TAG"
else
  echo "  —  no tag $TAG"
fi

# 4. --hard reset (optional)
if [[ "$MODE" == "--hard" ]]; then
  echo ""
  echo "⚠️  --hard mode: will also git reset --hard to remove refine+seal commits."
  read -r -p "   Confirm (type 'yes' to proceed): " confirm
  if [[ "$confirm" == "yes" ]]; then
    # Find the commit just before the refine commit for this phase
    BEFORE="$(git log --oneline | grep -v "phase-${PHASE}" | head -1 | awk '{print $1}')"
    if [[ -n "$BEFORE" ]]; then
      echo "  ↻  resetting to $BEFORE"
      git reset --hard "$BEFORE"
    else
      echo "  ⚠  could not locate pre-phase commit. Reset skipped." >&2
    fi
  else
    echo "  —  reset skipped (confirmation not given)"
  fi
fi

echo ""
echo "✅ Cleanup complete for Phase $PHASE"
