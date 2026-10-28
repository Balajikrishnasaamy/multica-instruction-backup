# Multica instruction backup

Everything about how the dev squads are configured, in one place. Mika (workspace chief of staff) is not managed here.

## Folders
- `rewritten/`  THE SOURCE OF TRUTH you edit. One file per agent and squad:
  `agents/<Name>.instructions.md`, `agents/<Name>.description.txt`, `squads/<Squad>.instructions.md`, `squads/<Squad>.description.txt`
- `applied/`    copy of `rewritten/` as of the last `apply.sh --apply`. Used to detect edits made in the Multica UI.
- `original/`   the config before any rewrite (agents.json, squads.json). `revert.sh` restores it.
- `history/`    timestamped snapshots of the live config (agents.json, squads.json) and the tools; last 30 kept.
- `lessons/`    the learning loop: LESSONS.md (approved lessons = the live skill `cirdoc-lessons`), proposals/ (every proposal and
                its status), audit.tsv (who/what/when), processed.tsv (issues already reviewed), config.json (skill, inbox issue,
                curator ids), history/ (previous LESSONS.md versions).
- `tools/`      latest copy of deploy_dev.sh, run_test.sh, lessons.py, Runner.java, report.py (the scripts the agents run).
                Live copies are in /Users/balaji-6091/Build/qntrl/. qntrl_run.sh is NOT backed up (it contains tokens).

## Changing the config
1. Edit files under `rewritten/` (descriptions must be 255 characters or fewer).
2. `bash apply.sh`            dry run
3. `bash apply.sh --apply`    snapshots the live state first, stops if someone edited the Multica UI since the last apply,
                              pushes everything, and records `applied/`.
4. `bash snapshot.sh`         any time: saves the live config to history/ and reports drift. Run it after you change anything.

## If you edited something in the Multica UI
- `bash snapshot.sh`          shows what differs from the last applied state
- `bash snapshot.sh --adopt`  keeps the UI edits: copies the live text into `rewritten/` and `applied/`
- `bash apply.sh --apply --force`  overwrites the UI edits with `rewritten/` instead

## If you edit a script in /Users/balaji-6091/Build/qntrl/
Run `bash snapshot.sh` afterwards so `tools/` and `history/` get the new version.

## Revert
`bash revert.sh --apply` restores `original/`.

## Current settings
- MR targets: circuit -> CIRCUIT_KB_STAGING, qntrlworker -> QW_KB_BRANCH, qntrlcore -> KB_BP_FINAL_BRANCH
- Automated tests: circuit only (run_test.sh writes an HTML report on every run)

## Learning loop (agents improve from every issue)
- Every agent loads the skill `cirdoc-lessons` at the start of each run (sections: All agents, Worker, Reviewer, Classify & Route, Planning, Lessons Curator).
- Agents end a comment with a LESSON block when something real cost them time. It is only a proposal.
- Classify & Route mentions **Lessons Curator** only on troubled issues (failed run, BLOCKED/ESCALATE, round or test_cycle 2+, LESSON block, blocked). You can also mention it on any issue yourself.
- Curator runs `lessons.py scan <issue>` (masked evidence), drops duplicates, and posts at most 3 proposals on the inbox issue (CIRD-25).
- A proposal changes nothing until you reply on CIRD-25 with `APPROVE <proposal-id>` (or `REJECT <id>: reason`). `lessons.py` refuses any change without that human comment.
- Approved lessons are written to `lessons/LESSONS.md` AND pushed to the live skill in one step, so the backup is updated automatically.
- Retire an outdated lesson the same way: Curator proposes `RETIRE <lesson id>`, you approve.
- If you edit the skill in the Multica UI: `bash snapshot.sh` reports the drift; `python3 /Users/balaji-6091/Build/qntrl/lessons.py sync --adopt` keeps the live text, `--push` overwrites it with the backup.
- Instruction changes (not lessons) are only ever suggested by Curator ("INSTRUCTION-CHANGE SUGGESTION"); I apply them through rewritten/ and apply.sh.
