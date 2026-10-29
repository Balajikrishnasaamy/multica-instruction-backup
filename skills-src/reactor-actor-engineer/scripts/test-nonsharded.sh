#!/usr/bin/env bash
# Non-sharded-mode static validation checklist.
# Default in-repo: reactor.sharding.enabled=false (server.conf).
# No automated reactor non-sharded suite exists; this is static review only.
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

echo "=== test-nonsharded (static dual-mode review) ==="
info "target mode: reactor.sharding.enabled=false (repo default)"

# Confirm default
if grep -A6 -E 'sharding\s*\{' product_package/conf/ReactorWorker/server.conf | grep -qE 'enabled:\s*false'; then
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
  if has_re "$sym" "$REACTOR"; then
    ok "symbol present: $sym"
  else
    bad "symbol missing: $sym"
  fi
done

# Non-sharded silent-drop risk (known-issues K2)
if has_re 'checkServerDependency|sendAsyncMessage' "$REACTOR/service"; then
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
