#!/bin/bash
# Restores the ORIGINAL instructions/descriptions saved in original/agents.json and original/squads.json.
set -euo pipefail
export MULTICA_WORKSPACE_ID=85121eb5-c9c7-4018-a975-140810c991cb
M=(/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica --profile desktop-api.multica.ai)
D="$(cd "$(dirname "$0")" && pwd)/original"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
python3 - "$D" "$APPLY" "${M[@]}" <<'PY'
import json, subprocess, sys, html
D, apply, M = sys.argv[1], sys.argv[2] == "1", sys.argv[3:]
def load(k):
    d = json.load(open(f"{D}/{k}.json")); return d if isinstance(d, list) else d[k]
for kind, items in (("agent", load("agents")), ("squad", load("squads"))):
    for it in items:
        if kind == "agent" and it["name"] == "Mika": continue
        cmd = M + [kind, "update", it["id"], "--instructions", html.unescape(it.get("instructions") or ""), "--description", html.unescape(it.get("description") or ""), "--output", "json"]
        if apply: subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL); print("restored", kind, it["name"])
        else: print("would restore", kind, it["name"])
PY
