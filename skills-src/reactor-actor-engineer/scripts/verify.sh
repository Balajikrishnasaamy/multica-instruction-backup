#!/usr/bin/env bash
# Static + build verification for reactor-actor-engineer tasks.
# Safe/deterministic: no credential mutation, no cluster start.
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

fail=0
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
info() { printf 'INFO  %s\n' "$*"; }

echo "=== reactor-actor-engineer verify ==="
echo "repo: $ROOT"

# --- required paths ---
required=(
  "source/reactor/com/qntrl/worker/reactor/actors/SupervisorActor.java"
  "source/reactor/com/qntrl/worker/reactor/actors/RecoveryCoordinatorActor.java"
  "source/reactor/com/qntrl/worker/reactor/main/ReactorWorker.java"
  "product_package/conf/ReactorWorker/server.conf"
  "product_package/conf/ReactorWorker/application.conf"
  "product_package/conf/ReactorWorker/actor.conf"
  "build/local_build/run.sh"
  "build/ant.properties"
)

for p in "${required[@]}"; do
  if [[ -f "$p" ]]; then ok "exists $p"; else bad "missing $p"; fi
done

# --- config defaults present ---
if has_re 'sharding\s*\{' product_package/conf/ReactorWorker/server.conf \
  && has_re 'enabled:\s*false' product_package/conf/ReactorWorker/server.conf; then
  ok "server.conf has reactor.sharding block (default enabled:false expected)"
else
  bad "server.conf sharding block / default not found"
fi

if has_re 'sequential-actor' product_package/conf/ReactorWorker/application.conf; then
  ok "application.conf has akka.actor.sequential-actor"
else
  bad "sequential-actor config missing"
fi

# --- reactor jar wiring in ant.properties ---
if has_re 'reactor_jartask=.*qntrl-worker-reactor\.jar' build/ant.properties; then
  ok "ant.properties defines reactor_jartask"
else
  bad "reactor_jartask missing from build/ant.properties"
fi

if has_re 'source/reactor/\*\*' build/ant.properties; then
  ok "source/reactor included in compile sources"
else
  bad "source/reactor not in source_compile_includes"
fi

# --- no false confidence: document missing automated reactor tests ---
if has_re 'org\.junit|akka\.testkit|TestKit' source/reactor; then
  info "JUnit/TestKit references found under source/reactor — re-check before claiming coverage"
else
  info "no JUnit/Akka TestKit under source/reactor (expected as of repo scan)"
fi

# --- optional compile ---
# Full product build: bash build/local_build/run.sh → ant -Dpdt_name=qntrlworker
# Requires ANT_HOME/JAVA_HOME (run.sh has machine-local fallbacks).
if [[ "${VERIFY_COMPILE:-0}" == "1" ]]; then
  info "VERIFY_COMPILE=1 → running build/local_build/run.sh"
  if [[ ! -x build/local_build/run.sh ]]; then
    chmod +x build/local_build/run.sh || true
  fi
  (cd build/local_build && bash ./run.sh)
  ok "local ant build finished (ant -Dpdt_name=qntrlworker)"
else
  info "skip compile (set VERIFY_COMPILE=1 to run: bash build/local_build/run.sh)"
  info "exact ant invocation inside run.sh: ant -Dpdt_name=qntrlworker"
fi

echo "=== summary ==="
if [[ "$fail" -ne 0 ]]; then
  echo "verify FAILED"
  exit 1
fi
echo "verify PASSED (static checks)"
exit 0
