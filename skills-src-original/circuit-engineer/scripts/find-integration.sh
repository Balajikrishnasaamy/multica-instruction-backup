#!/usr/bin/env bash
# Usage: ./find-integration.sh <ServiceName>
# Example: ./find-integration.sh ZohoCRM
# Finds all files related to a given integration service.

set -e

NAME="${1:-}"
if [ -z "$NAME" ]; then
  echo "Usage: $0 <ServiceName>  (e.g. ZohoCRM, ZohoCatalyst, Bridge, DRE, Okta, AzureUser)"
  exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SOURCE="$REPO_ROOT/source"

echo "=== Service enum entry ==="
grep -n "$NAME" "$SOURCE/worker/com/qntrl/circuit/integration/Service.java" 2>/dev/null | head -10 || echo "(not found in Service.java)"

echo ""
echo "=== Integration handler directory ==="
find "$SOURCE/worker/com/qntrl/circuit/integration" -maxdepth 2 -iname "*${NAME}*" 2>/dev/null || echo "(not found)"

echo ""
echo "=== TaskOperation enum (executor) ==="
find "$SOURCE/executor/com/qntrl/execution/constant" -iname "*${NAME}*" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Actor (executor) ==="
find "$SOURCE/executor/com/qntrl/execution/actor" -iname "*${NAME}*" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Controller (worker) ==="
find "$SOURCE/worker/com/qntrl/circuit/controller" -iname "*${NAME}*Controller.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== circuit.conf entry ==="
grep -n "$NAME" "$REPO_ROOT/product_package/conf/circuit.conf" 2>/dev/null | head -5 \
  || grep -rn "$NAME" "$REPO_ROOT/product_package/conf" --include="*.conf" 2>/dev/null | head -5 \
  || echo "(circuit.conf not found or service not in conf)"

echo ""
echo "=== All source references (top 20) ==="
grep -rn "\b${NAME}\b" "$SOURCE" --include="*.java" -l 2>/dev/null | head -20 || true
