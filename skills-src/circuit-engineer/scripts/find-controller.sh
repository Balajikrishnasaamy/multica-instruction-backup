#!/usr/bin/env bash
# Usage: ./find-controller.sh <ResourceName>
# Example: ./find-controller.sh Circuit
# Finds the controller, handler, bean, and response files for a given resource name.

set -e

NAME="${1:-}"
if [ -z "$NAME" ]; then
  echo "Usage: $0 <ResourceName>  (e.g. Circuit, State, Action, Webhook)"
  exit 1
fi

. "$(dirname "$0")/_root.sh"
WORKER="$REPO_ROOT/source/worker/com/qntrl/circuit"
NAME_LOWER="$(echo "$NAME" | tr '[:upper:]' '[:lower:]')"

echo "=== Controller ==="
find "$WORKER/controller" -iname "${NAME}*Controller.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Handler ==="
find "$WORKER/handler" -iname "${NAME}*Handler.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Request Bean ==="
find "$WORKER/bean" -iname "${NAME}*Bean.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Response ==="
find "$WORKER/response" -iname "${NAME}*Response*.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== DB DataAccess / DataSet ==="
find "$WORKER/db" -iname "*${NAME}*" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Security XML entries ==="
grep -n "${NAME_LOWER}" \
  "$REPO_ROOT/product_package/conf/Security/QntrlCircuit/security-web.xml" \
  "$REPO_ROOT/product_package/conf/Security/QntrlCircuit/security-api.xml" \
  2>/dev/null | head -20 || echo "(not found in security XML)"
