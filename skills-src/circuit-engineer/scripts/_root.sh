# Sourced by the find-*.sh scripts. Sets REPO_ROOT to the circuit checkout. Works with macOS bash 3.2.
# Order: CIRCUIT_REPO_ROOT, the git repository you are standing in, ./circuit (Multica workdir layout),
# then the repository that contains this script.
_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
if [ -n "${CIRCUIT_REPO_ROOT:-}" ]; then
  REPO_ROOT="$CIRCUIT_REPO_ROOT"
else
  _r="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_r" ] && [ -d "$_r/source/worker" ]; then REPO_ROOT="$_r"
  elif [ -d "./circuit/source/worker" ]; then REPO_ROOT="$(cd ./circuit && pwd)"
  else
    _r="$(git -C "$_self" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$_r" ] && [ -d "$_r/source/worker" ]; then REPO_ROOT="$_r"; fi
  fi
fi
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/source/worker" ]; then
  echo "ERROR: cannot find the circuit checkout. Run from inside it, or set CIRCUIT_REPO_ROOT=<path>." >&2
  exit 1
fi
