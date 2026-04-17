#!/usr/bin/env bash
# relay-sync.sh — Re-sync wrappers in N target repos with plugin.
#
# Usage:
#   relay-sync.sh <target-repo-path> [<target-repo-path> ...]
#
# Convenience wrapper that calls relay-install.sh per target.
# Use when you update wrappers in the plugin and want to propagate.

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <target-repo-path> [<target-repo-path> ...]" >&2
  exit 1
fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for target in "$@"; do
  echo ""
  echo "--- Syncing $target ---"
  "$PLUGIN_ROOT/scripts/relay-install.sh" "$target"
done

echo ""
echo "✅ Synced $# target(s)"
