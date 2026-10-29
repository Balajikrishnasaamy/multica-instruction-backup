#!/usr/bin/env bash
# Sharded-mode static validation checklist.
# Repo reality: there is NO automated reactor sharding test suite.
# This script verifies sources/config paths for sharding.enabled=true behavior.
set -euo pipefail

command -v rg >/dev/null 2>&1 || { echo "ERROR: ripgrep (rg) is required but not installed. Install via: brew install ripgrep"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Repo root: explicit override > git toplevel > relative fallback (skill installed at .claude/skills/<name>/scripts/)
ROOT="${REACTOR_REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../../../.." && pwd))}"
cd "$ROOT"
REACTOR="source/reactor/com/qntrl/worker/reactor"

fail=0
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
info() { printf 'INFO  %s\n' "$*"; }

echo "=== test-sharded (static dual-mode review) ==="
info "target mode: reactor.sharding.enabled=true"
info "default in server.conf is false — runtime must override for live shard clusters"

# Config keys
if rg -n 'sharding\s*\{' product_package/conf/ReactorWorker/server.conf >/dev/null; then
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
  if rg -q --glob '*.java' "$sym" "$REACTOR"; then
    ok "symbol present: $sym"
  else
    bad "symbol missing: $sym"
  fi
done

# MemberRemoved path is sharded-only concern
if rg -q 'MEMBER_REMOVED|MemberRemoved|RECOVER_AFTER_MEMBER_REMOVED' \
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
