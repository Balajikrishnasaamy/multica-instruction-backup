#!/bin/bash
# Applies ~/multica-instruction-backup/rewritten/* to the live Multica workspace.
# NOT run automatically. Run:  bash apply.sh            (dry run, prints what would change)
#                              bash apply.sh --apply    (writes)
# Revert:                      bash revert.sh --apply   (restores original/ instructions + descriptions)
set -euo pipefail
export MULTICA_WORKSPACE_ID=85121eb5-c9c7-4018-a975-140810c991cb
M=(/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica --profile desktop-api.multica.ai)
D="$(cd "$(dirname "$0")" && pwd)/rewritten"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
if [ $APPLY -eq 1 ]; then
	# keep a copy of what is live right now, and refuse to overwrite unsaved UI edits silently
	out=$(bash "$(dirname "$0")/snapshot.sh"); echo "$out" | grep -E "DRIFT|snapshot saved"
	if echo "$out" | grep -q DRIFT && [ "${2:-}" != "--force" ]; then echo "STOP: live config has edits that are not in rewritten/. Run: bash snapshot.sh --adopt  (keep them)  or  bash apply.sh --apply --force  (overwrite them)."; exit 1; fi
fi
run() { if [ $APPLY -eq 1 ]; then "${M[@]}" "$@" --output json >/dev/null && echo "updated: $1 $2 $3"; else echo "would run: multica $1 $2 $3 ..."; fi; }
agent() { # id name
	run agent update "$1" --instructions "$(cat "$D/agents/$2.instructions.md")" --description "$(cat "$D/agents/$2.description.txt")"; }
squad() { run squad update "$1" --instructions "$(cat "$D/squads/$2.instructions.md")" --description "$(cat "$D/squads/$2.description.txt")"; }
agent f95aa45d-92b8-450f-a4ec-729c79573e72 "Classify & Route"
agent bc49308c-248d-44c4-98eb-8e4bdcf18e98 "Reviewer"
agent aebc1881-39eb-4cad-a6e5-9fe210da4910 "Worker-1"
agent 66cfb32d-5df9-4caf-92cd-a54aa4af0ed9 "Worker-O"
agent 5b8fb0b2-e164-4f4e-bf7b-83c58717df17 "Worker"
agent 241d346d-29be-4dc1-a6fb-e784e9f83091 "Plan Lead"
agent d52422ed-aeaa-4846-b2d9-17f63249b54b "Requirements Analyst"
agent 7ba055ff-fbc0-42bd-8da4-c65d07a07fd0 "Feasibility Engineer"
agent 5478839a-154d-4b65-a512-8776c0a6facd "Lessons Curator"
squad 6c2ea9dc-5688-40d2-8013-d25b816b281d CirDoc-P
squad 302551ad-d3b1-4c66-b883-c57d99ecd84e CirDoc-O
squad a821bc06-a226-40bb-adc3-f09d7e727cfa CirDoc
squad 3eae1695-1b7b-4abb-b87d-4279f2e1bc5f CirDoc-Plan
[ $APPLY -eq 1 ] && { rm -rf "$(dirname "$0")/applied" && cp -R "$D" "$(dirname "$0")/applied" && echo "recorded applied state"; }
