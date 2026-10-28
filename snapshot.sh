#!/bin/bash
# Saves the CURRENT live Multica config and the tooling into history/<timestamp>/ and reports drift.
#   bash snapshot.sh          snapshot + drift report (nothing is changed in Multica or in rewritten/)
#   bash snapshot.sh --adopt  also copy live instructions/descriptions into rewritten/ (use after editing in the Multica UI)
# apply.sh runs this automatically before it writes anything.
set -uo pipefail
export MULTICA_WORKSPACE_ID=85121eb5-c9c7-4018-a975-140810c991cb
M=(/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica --profile desktop-api.multica.ai)
ROOT="$(cd "$(dirname "$0")" && pwd)"
ADOPT=0; [ "${1:-}" = "--adopt" ] && ADOPT=1
H="$ROOT/history/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$H"
"${M[@]}" agent list --output json > "$H/agents.json" || { echo "could not read agents"; exit 1; }
"${M[@]}" squad list --output json > "$H/squads.json" || { echo "could not read squads"; exit 1; }
# tooling (qntrl_run.sh is deliberately NOT copied: it contains tokens)
mkdir -p "$H/tools"
B=/Users/balaji-6091/Build/qntrl
cp "$B/deploy_dev.sh" "$B/run_test.sh" "$B/lessons.py" "$H/tools/" 2>/dev/null
cp "$B/testlib/Runner.java" "$B/testlib/report.py" "$H/tools/" 2>/dev/null
rm -rf "$ROOT/tools" && cp -R "$H/tools" "$ROOT/tools"
python3 - "$ROOT" "$H" "$ADOPT" <<'PY'
import html, json, os, sys
root, h, adopt = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
def load(k):
    d = json.load(open(f"{h}/{k}.json")); return d if isinstance(d, list) else d[k]
drift = 0
for kind, items in (("agents", load("agents")), ("squads", load("squads"))):
    for it in items:
        name = it["name"]
        for field, ext in (("instructions", "instructions.md"), ("description", "description.txt")):
            path = f"{root}/rewritten/{kind}/{name}.{ext}"
            base = f"{root}/applied/{kind}/{name}.{ext}"   # what we last pushed to Multica
            if not os.path.exists(path): continue
            if not os.path.exists(base): base = path   # e.g. Mika: not managed here
            live = html.unescape(it.get(field) or "").strip()
            mine = open(base).read().strip()
            if live != mine:
                drift += 1
                print(f"DRIFT {kind[:-1]} {name} {field}: live differs from what was last applied (edited in the Multica UI?)")
                if adopt:
                    open(path, "w").write(live + "\n"); os.makedirs(os.path.dirname(base), exist_ok=True); open(base, "w").write(live + "\n"); print("  adopted live value into", os.path.relpath(path, root))
print("no drift: live workspace matches what was last applied" if not drift else f"{drift} difference(s)" + ("" if adopt else " (run: bash snapshot.sh --adopt  to keep the live values, or bash apply.sh --apply to overwrite them)"))
PY
# lessons skill: report drift between lessons/LESSONS.md and the live skill (never overwrites)
if [ -f "$ROOT/lessons/config.json" ]; then python3 "$B/lessons.py" sync 2>&1 | head -2; fi
echo "snapshot saved: $H"
ls -1d "$ROOT"/history/*/ | sort -r | tail -n +31 | while IFS= read -r old; do rm -rf "$old"; done
