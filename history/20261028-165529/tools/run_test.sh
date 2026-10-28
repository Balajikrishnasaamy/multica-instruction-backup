#!/bin/bash
# run_test.sh — run targeted JUnit 5 test classes for the circuit repo (no Ant/Maven/Gradle) and
# write an HTML report on EVERY run (pass, fail, compile error, no tests, timeout).
#
# Usage:
#   run_test.sh --repo circuit --src <checkout> --class <fully.qualified.TestClass>[#method] [--class ...]
#               [--issue <ISSUE-IDENT>] [--timeout <sec>] [--report-dir <dir>]
#
# Scope: circuit only for now. qntrlworker and qntrlcore are rejected with exit 2.
#
# It compiles the checkout's own sources plus the requested test classes against the dev build's jars
# (so it tests the code in that checkout, committed or not), then runs them with the JUnit launcher.
#
# Output ends with two lines:
#   RESULT: PASS, <n> tests   |   RESULT: FAIL, <failed> of <n> tests   |   RESULT: ERROR, <reason>
#   REPORT: <absolute path to index.html>
# The report folder is  <report-dir>/<timestamp>_<issue-or-repo>_<sha10>/index.html  (default report-dir:
# /Users/balaji-6091/Build/qntrl/test-reports; newest copy always at <report-dir>/latest.html; last 40 kept).
# Attach it to the issue comment with: multica issue comment add <issue> --attachment <path-to-index.html>
#
# Exit codes: 0 pass | 1 test failure | 2 usage | 3 compile error | 4 test class not found / no tests ran | 5 timeout
set -uo pipefail

BUILD=/Users/balaji-6091/Build/qntrl
SAS=$BUILD/AdventNet/Sas
LIB=$SAS/tomcat/webapps/ROOT/WEB-INF/lib
TESTLIB=$BUILD/testlib
REPORTS=$BUILD/test-reports
KEEP_REPORTS=40
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH=$JAVA_HOME/bin:$PATH

REPO=""; SRC=""; ISSUE=""; TIMEOUT=600; CLASSES=()
START_TS=$(date +%s); START_HUMAN=$(date '+%F %T')
STATUS=ERROR; SUMMARY=""; PHASE=setup; EXIT=2; COMPILE_LOG=""

while [ $# -gt 0 ]; do
	case "$1" in
		--repo) REPO=$2; shift 2 ;;
		--src) SRC=$2; shift 2 ;;
		--class) CLASSES+=("$2"); shift 2 ;;
		--issue) ISSUE=$2; shift 2 ;;
		--timeout) TIMEOUT=$2; shift 2 ;;
		--report-dir) REPORTS=$2; shift 2 ;;
		-h|--help) sed -n '2,24p' "$0"; exit 0 ;;
		*) echo "RESULT: ERROR, unknown arg: $1"; exit 2 ;;
	esac
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/run_test.XXXXXX")
OUT=$TMP/classes; mkdir -p "$OUT"
: > "$TMP/run.log"; : > "$TMP/results.tsv"

# ---- always produce a report and the final two lines, whatever happens ----
finish() {
	local rc=$?
	[ -n "${FINISHED:-}" ] && return; FINISHED=1
	local sha="nosha" dirty=false branch=""
	if [ -n "$SRC" ] && git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
		sha=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo nosha)
		branch=$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null)
		[ -n "$(git -C "$SRC" status --porcelain -- source test 2>/dev/null)" ] && dirty=true
	fi
	local label=${ISSUE:-${REPO:-run}}; label=$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '_')
	local dir="$REPORTS/$(date +%Y%m%d-%H%M%S)_${label}_${sha:0:10}_$$"
	mkdir -p "$dir" 2>/dev/null
	local dur=$(( $(date +%s) - START_TS ))
	local cmd="run_test.sh --repo ${REPO:-?} --src ${SRC:-?}"; for c in "${CLASSES[@]:-}"; do [ -n "$c" ] && cmd="$cmd --class $c"; done
	python3 - "$TMP/meta.json" "$REPO" "$SRC" "$branch" "$sha" "$dirty" "$STATUS" "$SUMMARY" "$PHASE" "$START_HUMAN" "$dur" "$cmd" "$TMP/javac.log" "${CLASSES[*]:-}" <<-'PY' 2>/dev/null
	import json, subprocess, sys
	(path, repo, src, branch, sha, dirty, status, summary, phase, started, dur, cmd, javac_log, classes) = sys.argv[1:15]
	try: compile_log = open(javac_log, errors="replace").read() if phase == "compile" else ""
	except OSError: compile_log = ""
	try: java = subprocess.check_output(["java", "-version"], stderr=subprocess.STDOUT, text=True).splitlines()[0]
	except Exception: java = "unknown"
	json.dump({"repo": repo or "?", "src": src or "?", "branch": branch, "sha": sha, "dirty": dirty == "true",
	           "classes": [c for c in classes.split() if c], "command": cmd, "status": status, "summary": summary,
	           "phase": phase, "started": started, "duration_s": int(dur), "java": java, "compile_log": compile_log}, open(path, "w"))
	PY
	if python3 "$TESTLIB/report.py" "$TMP/meta.json" "$TMP/results.tsv" "$TMP/run.log" "$dir/index.html" 2>"$TMP/report.err"; then
		cp "$dir/index.html" "$REPORTS/latest.html" 2>/dev/null
		# prune old report folders
		ls -1d "$REPORTS"/*/ 2>/dev/null | sort -r | tail -n +$((KEEP_REPORTS + 1)) | while IFS= read -r old; do rm -rf "$old"; done
		echo "RESULT: $STATUS, $SUMMARY"
		echo "REPORT: $dir/index.html"
	else
		echo "RESULT: $STATUS, $SUMMARY"
		echo "REPORT: (could not be generated: $(head -c 200 "$TMP/report.err"))"
	fi
	rm -rf "$TMP"
	exit "${EXIT:-$rc}"
}
trap finish EXIT

fail() { # status exit summary
	STATUS=$1; EXIT=$2; SUMMARY=$3; echo "ERROR: $3" >&2; exit "$2"
}

[ -n "$REPO" ] || fail ERROR 2 "--repo circuit required"
[ "$REPO" = circuit ] || fail ERROR 2 "automated tests are circuit-only for now; '$REPO' is not supported"
[ ${#CLASSES[@]} -gt 0 ] || fail ERROR 2 "--class is required"
[ -d "$SRC" ] || fail ERROR 2 "--src '$SRC' is not a directory"
SRC=$(cd "$SRC" && pwd)
SRC_DIRS="source/worker source/executor source/store source/entity source/qntrl"; TEST_DIRS="test"

PHASE=setup
TESTFILES=(); RUNCLASSES=()
for c in "${CLASSES[@]}"; do
	cls=${c%%#*}; rel=$(echo "$cls" | tr . /).java; found=""
	for d in $TEST_DIRS $SRC_DIRS; do [ -f "$SRC/$d/$rel" ] && { found="$SRC/$d/$rel"; break; }; done
	[ -n "$found" ] || fail ERROR 4 "test class $cls not found under $SRC/test; check the package and file name"
	TESTFILES+=("$found"); RUNCLASSES+=("$c")
done

SOURCEPATH=""; for d in $SRC_DIRS $TEST_DIRS; do [ -d "$SRC/$d" ] && SOURCEPATH="$SOURCEPATH:$SRC/$d"; done
SOURCEPATH=${SOURCEPATH#:}
BUILDCP=$(find "$SAS/lib" "$SAS/tomcat/lib" "$LIB" -name '*.jar' | tr '\n' ':')
TESTCP=$(ls "$TESTLIB"/*.jar | tr '\n' ':')

PHASE=compile
echo "## compile (${#TESTFILES[@]} test class(es) + their dependencies from $SRC)"
if ! javac -nowarn -encoding UTF-8 --release 17 -proc:none -implicit:class -Xprefer:source -sourcepath "$SOURCEPATH" \
		-cp "$TESTCP$BUILDCP" -d "$OUT" "${TESTFILES[@]}" > "$TMP/javac.log" 2>&1; then
	grep -v '^Note:' "$TMP/javac.log" | head -50
	fail ERROR 3 "compile failed"
fi

# Resources that sit next to the sources (properties, xml) must be visible to the tests.
for d in $SRC_DIRS $TEST_DIRS; do
	[ -d "$SRC/$d" ] && ( cd "$SRC/$d" && find . -type f ! -name '*.java' ! -path './.*' -print0 | xargs -0 -I{} rsync -R {} "$OUT/" 2>/dev/null )
done
[ -d "$SRC/resources/test" ] && cp -R "$SRC/resources/test/." "$OUT/" 2>/dev/null

PHASE=run
echo "## run ${RUNCLASSES[*]}"
java --add-exports java.xml/com.sun.org.apache.xerces.internal.jaxp=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED \
	-Drunner.out="$TMP/results.tsv" \
	-cp "$OUT:$TESTLIB/runner:$TESTCP$BUILDCP" Runner "${RUNCLASSES[@]}" > "$TMP/run.log" 2>&1 < /dev/null &
PID=$!
# Poll instead of a background watchdog: a leftover `sleep` would keep the caller's output pipe open.
waited=0
while kill -0 $PID 2>/dev/null; do
	if [ $waited -ge "$TIMEOUT" ]; then
		kill -9 $PID 2>/dev/null; wait $PID 2>/dev/null
		tail -20 "$TMP/run.log" | cut -c1-300
		fail ERROR 5 "timed out after ${TIMEOUT}s"
	fi
	sleep 1; waited=$((waited + 1))
done
wait $PID; RC=$?

# Drop framework INFO noise (it can include config values) and cap line length before showing output.
grep -v '^\(SLF4J\|WARNING\|INFO:\)' "$TMP/run.log" | grep -v 'com\.zoho\.conf\.Configuration' | cut -c1-300 | tail -60
LINE=$(grep '^RESULT found=' "$TMP/run.log" | tail -1)
FOUND=$(echo "$LINE" | sed -n 's/.* found=\([0-9]*\).*/\1/p'); PASSED=$(echo "$LINE" | sed -n 's/.* passed=\([0-9]*\).*/\1/p'); FAILED=$(echo "$LINE" | sed -n 's/.* failed=\([0-9]*\).*/\1/p')
[ -n "$LINE" ] || fail ERROR 4 "runner produced no summary (JVM crash?)"
[ "${FOUND:-0}" -gt 0 ] || fail ERROR 4 "no tests found in ${RUNCLASSES[*]} (missing @Test?)"
if [ $RC -eq 0 ]; then STATUS=PASS; EXIT=0; SUMMARY="$PASSED tests"; exit 0; fi
STATUS=FAIL; EXIT=1; SUMMARY="$FAILED of $FOUND tests"; exit 1
