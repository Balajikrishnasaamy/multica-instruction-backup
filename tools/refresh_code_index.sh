#!/bin/bash
# Rebuild the circuit code index from CIRCUIT_KB_STAGING and upload it to the Multica skill 'cirdoc-code-index'.
# Run:  bash tools/refresh_code_index.sh   (read-only on the repo; safe any time)
set -euo pipefail
cd "$(dirname "$0")/.."
export MULTICA_WORKSPACE_ID=85121eb5-c9c7-4018-a975-140810c991cb
M=(/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica --profile desktop-api.multica.ai)
REPO=${CIRCUIT_REPO:-$HOME/Cursor/circuit}
git -C "$REPO" fetch -q origin CIRCUIT_KB_STAGING
python3 tools/build_index.py "$REPO" origin/CIRCUIT_KB_STAGING code-index/circuit-index.md
ID=$("${M[@]}" skill list --output json | python3 -c "import json,sys;print(next(s['id'] for s in json.load(sys.stdin) if s['name']=='cirdoc-code-index'))")
"${M[@]}" skill files upsert "$ID" --path circuit-index.md --content-file code-index/circuit-index.md --output json >/dev/null
echo "uploaded circuit-index.md to skill $ID ($(wc -c < code-index/circuit-index.md) bytes)"
