#!/usr/bin/env bash
# Usage: ./find-actor.sh <TaskTypeName>
# Example: ./find-actor.sh Branch
# Finds the Actor, Task, and related files for a given task type name.

set -e

NAME="${1:-}"
if [ -z "$NAME" ]; then
  echo "Usage: $0 <TaskTypeName>  (e.g. Branch, Action, Bridge, Parallel)"
  exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SOURCE="$REPO_ROOT/source"

echo "=== TaskType enum entry ==="
grep -n "${NAME^^}" "$SOURCE/executor/com/qntrl/execution/constant/TaskType.java" || true

echo ""
echo "=== Actor class ==="
find "$SOURCE/executor/com/qntrl/execution/actor" -name "${NAME}Actor.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Task class ==="
find "$SOURCE/executor/com/qntrl/execution/task" -name "${NAME}Task.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Handler (worker module) ==="
find "$SOURCE/worker/com/qntrl/circuit/handler" -name "${NAME}Handler.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== Controller (worker module) ==="
find "$SOURCE/worker/com/qntrl/circuit/controller" -iname "${NAME}*Controller.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== TaskOperation enum (if any) ==="
find "$SOURCE/executor/com/qntrl/execution/constant" -name "${NAME}*TaskOperation.java" 2>/dev/null || echo "(not found)"

echo ""
echo "=== All references in source ==="
grep -rn "class ${Name}Actor\|class ${NAME}Actor\|${NAME}Actor\b" "$SOURCE" --include="*.java" -l 2>/dev/null | head -10 || true
