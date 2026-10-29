#!/usr/bin/env bash
# Sharded-mode static validation checklist.
# Repo reality: there is NO automated reactor sharding test suite.
# This script verifies sources/config paths for sharding.enabled=true behavior.
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root: REACTOR_REPO_ROOT > the git repo you are standing in > ./qntrlworker (Multica workdir layout) > the repo containing this script
ROOT=""
if [ -n "${REACTOR_REPO_ROOT:-}" ]; then ROOT="$REACTOR_REPO_ROOT"
else
  _r="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_r" ] && [ -d "$_r/source/reactor" ]; then ROOT="$_r"
  elif [ -d "./qntrlworker/source/reactor" ]; then ROOT="$(cd ./qntrlworker && pwd)"
  else _r="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"; [ -n "$_r" ] && [ -d "$_r/source/reactor" ] && ROOT="$_r"; fi
fi
[ -n "$ROOT" ] && [ -d "$ROOT/source/reactor" ] || { echo "ERROR: cannot find the qntrlworker checkout. Run from inside it, or set REACTOR_REPO_ROOT=<path>."; exit 1; }
cd "$ROOT"
# --- portable search helper: plain grep (no ripgrep needed; works with macOS bash 3.2 and BSD grep) ---
# has_re <regex> <file-or-dir>...  -> exit 0 if the extended regex matches (dirs: recursive over java/conf/properties)
has_re() {
  local re="$1"; shift; local t
  for t in "$@"; do
    if [ -d "$t" ]; then grep -rqE --include='*.java' --include='*.conf' --include='*.properties' -e "$re" "$t" 2>/dev/null && return 0
    else grep -qE -e "$re" "$t" 2>/dev/null && return 0; fi
  done
  return 1
}
REACTOR="source/reactor/com/qntrl/worker/reactor"

fail=0
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
info() { printf 'INFO  %s\n' "$*"; }

echo "=== test-sharded (static dual-mode review) ==="
info "target mode: reactor.sharding.enabled=true"
info "default in server.conf is false — runtime must override for live shard clusters"

# Config keys
if has_re 'sharding\s*\{' product_package/conf/ReactorWorker/server.conf; then
  ok "server.conf sharding block present"
else
  bad "server.conf sharding block missing"
fi

# Bootstrap / shard entry points must exist
for rel in \
  "main/ReactorWorker.java" \
  "sharding/ProcessorShardBootstrap.java" \
  "config/ReactorServerConfiguration.java"
do
  if [[ -f "$REACTOR/$rel" ]]; then ok "open $rel"; else bad "missing $rel"; fi
done

# Sharded routing symbols (presence, not behavioral proof)
checks=(
  "initShardedActorSystem"
  "ProcessorShard"
  "SequentialShard"
  "ShardEnvelope"
  "startFreshProcess"
  "recoverProcess"
)
for sym in "${checks[@]}"; do
  if has_re "$sym" "$REACTOR"; then
    ok "symbol present: $sym"
  else
    bad "symbol missing: $sym"
  fi
done

# MemberRemoved path is sharded-only concern
if has_re 'MEMBER_REMOVED|MemberRemoved|RECOVER_AFTER_MEMBER_REMOVED' \
  "$REACTOR/actors/SupervisorActor.java"; then
  ok "SupervisorActor has member-removed recover path"
else
  bad "member-removed recover markers not found in SupervisorActor"
fi

info "manual checklist before claiming sharded Done:"
info "  1. Diff reviewed against ProcessorShardBootstrap + SequentialShard routes"
info "  2. abort/resume/retry/partial-restart use bundle-then-message ShardEnvelope"
info "  3. migration.enabled interaction considered for boot recovery only"
info "  4. outbound rate limiter ClusterSingleton semantics considered"
info "  5. no automated suite — deploy/runtime proof is outside this script"

echo "=== summary ==="
if [[ "$fail" -ne 0 ]]; then
  echo "test-sharded FAILED"
  exit 1
fi
echo "test-sharded PASSED (static). Runtime sharded proof: set reactor.sharding.enabled=true in deployed server.conf and exercise cluster."
exit 0
