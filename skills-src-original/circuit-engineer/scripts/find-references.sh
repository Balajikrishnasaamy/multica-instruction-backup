#!/usr/bin/env bash
# Usage: ./find-references.sh <Symbol>
# Example: ./find-references.sh ReactorWrapper
# Finds all Java files that reference (import or use) the given symbol.

set -e

SYMBOL="${1:-}"
if [ -z "$SYMBOL" ]; then
  echo "Usage: $0 <Symbol>  (e.g. ReactorWrapper, ExecutorHandler, BranchActor)"
  exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SOURCE="$REPO_ROOT/source"

echo "=== Java files referencing '$SYMBOL' ==="
grep -rn "\b${SYMBOL}\b" "$SOURCE" --include="*.java" -l 2>/dev/null | sort || echo "(none found)"

echo ""
echo "=== Usages (file:line) ==="
grep -rn "\b${SYMBOL}\b" "$SOURCE" --include="*.java" 2>/dev/null | head -40 || echo "(none found)"
