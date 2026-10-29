#!/usr/bin/env bash
# Non-sharded-mode static validation checklist.
# Default in-repo: reactor.sharding.enabled=false (server.conf).
# No automated reactor non-sharded suite exists; this is static review only.
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

echo "=== test-nonsharded (static dual-mode review) ==="
info "target mode: reactor.sharding.enabled=false (repo default)"

# Confirm default
if rg -A6 'sharding\s*\{' product_package/conf/ReactorWorker/server.conf | rg -q 'enabled:\s*false'; then
  ok "server.conf default sharding.enabled: false"
else
  bad "could not confirm sharding.enabled: false default"
fi

for rel in \
  "main/ReactorWorker.java" \
  "actors/SupervisorActor.java" \
  "service/ReactorActions.java" \
  "service/DataHelper.java"
do
  if [[ -f "$REACTOR/$rel" ]]; then ok "open $rel"; else bad "missing $rel"; fi
done

checks=(
  "initNonShardedActorSystem"
  "handleStartProcess"
  "withoutSplitBrainResolver"
)
for sym in "${checks[@]}"; do
  if rg -q --glob '*.java' "$sym" "$REACTOR"; then
    ok "symbol present: $sym"
  else
    bad "symbol missing: $sym"
  fi
done

# Non-sharded silent-drop risk (known-issues K2)
if rg -q 'checkServerDependency|sendAsyncMessage' "$REACTOR/service"; then
  ok "DataHelper/ReactorActions async path present (review drop behavior on change)"
else
  bad "async send helpers missing"
fi

info "manual checklist before claiming non-sharded Done:"
info "  1. start path uses supervisor handleStartProcess (not ProcessorShardBootstrap)"
info "  2. BundleMessage stays supervisor-local (not SequentialShard)"
info "  3. SBR stripped path still considered"
info "  4. local outboundRateLimiter (per-node rates) considered"
info "  5. DataHelper async drop behavior reviewed if touching response/resume"

echo "=== summary ==="
if [[ "$fail" -ne 0 ]]; then
  echo "test-nonsharded FAILED"
  exit 1
fi
echo "test-nonsharded PASSED (static). Runtime proof: deploy with reactor.sharding.enabled=false (default)."
exit 0
