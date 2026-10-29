# Differences between the Multica skills and the original .claude files

Source of the originals: `~/Cursor/circuit/.claude/` (skills/circuit-engineer + circuit-engineer/ pack) and
`~/Cursor/qntrlworker/.claude/skills/reactor-actor-engineer/`. Untouched copies: `skills-src-original/`.
Fixed copies (what Multica runs): `skills-src/`. See them with `diff -ru skills-src-original skills-src`.
The `.claude/` files in the repos were NOT changed. Port any of these back by hand if you want them at the source.

Verified against origin/CIRCUIT_KB_STAGING and origin/QW_KB_BRANCH on 2026-10-29.

## circuit-engineer
1. SKILL.md description: removed "main branch CIRCUIT_V3_STAGING". The MR target is CIRCUIT_KB_STAGING (26 commits behind V3_STAGING, which is only the repo default).
2. SKILL.md: new first sections "Working inside the Multica CirDoc squads" (workdir checkout, fixed MR target, commit/push per agent instructions, tests only via run_test.sh, no ant/mvn/gradle, only Reviewer deploys, AGENTS.md wins, ZRTask/ZRTaskActor/SystemActor live in qntrlworker, actors are not unit-testable) and "Knowledge pack" (which reference to load per task, pinned files).
3. SKILL.md Build: removed "rely on the IDE's compile output in out/" (no IDE in Multica); Safety: the "never commit or push" rule now applies outside the squads only.
4. references/actor-patterns.md: banner saying NOTIFY / NotifyTask / NotifyActor / NotifyTaskOperation are illustrative (no such class exists) and naming real examples (BranchActor, WebhookActor, CustomResourceTask, DateTimeTaskOperation); the example path of NotifyTaskOperation marked as an example; note that ZRTask, ZRTaskActor, SystemActor are in qntrlworker.
5. references/test-patterns.md: "Build Integration" now says run_test.sh only.
6. README.md: scripts can be pointed at the repo with CIRCUIT_REPO_ROOT.
7. scripts/_root.sh (new) and find-*.sh: no longer need the script to live inside the repo (CIRCUIT_REPO_ROOT, cwd repo, ./circuit, script's repo); `${NAME^^}` and `${NAME,,}` (bash 4 only, broke on macOS bash 3.2) replaced; find-actor.sh splits CamelCase to the enum name (CustomWebhook -> CUSTOM_WEBHOOK). Tested on /bin/bash 3.2 against the origin tree.
8. The agent file `.claude/agents/circuit-engineer.md` (model claude-opus-5, a session branch name, Agent/WebSearch tools) was NOT uploaded: it is Claude Code configuration, and its content is a subset of SKILL.md.
Known leftover: the integration-guide mentions of `InternalIntegratedServiceHandler` were already correct; only the agent file named a non-existent `IntegratedServiceHandler` (not uploaded).

## reactor-actor-engineer
1. SKILL.md: new section "Working inside the Multica CirDoc squads" (workdir checkout, MR target QW_KB_BRANCH not the repo default QNTRLWORKER_STAGING, commit/push per agent instructions, no test runner so HANDOFF says SKIPPED, run the static scripts, scripts live outside the repo so use REACTOR_REPO_ROOT, no ant, concrete actors SequentialActor/FailureTask/BranchActor are in the circuit repo, reactoragent out of scope).
2. SKILL.md Validation table: paths `.claude/skills/reactor-actor-engineer/scripts/...` replaced by `<this skill folder>/scripts/...`; the two build commands marked "not run in Multica"; "Worktree/branch isolation belongs to the outer orchestrator" replaced by a pointer to the Multica section.
3. scripts/verify.sh, test-sharded.sh, test-nonsharded.sh: ripgrep (`rg`) no longer required (plain grep via a has_re helper; behaviour checked, including that deleted files and renamed symbols still produce FAIL and exit 1); repo root found via REACTOR_REPO_ROOT, cwd repo, ./qntrlworker, or the script's repo, with a clear error otherwise. Tested on /bin/bash 3.2 without rg: all PASS on the real tree.
4. references/debugging.md and templates/implementation-report.md: script paths changed to `<skill folder>/scripts/...`.
5. agent-card.md: unchanged in the Multica copy except it is not a SKILL file (it is the agent-graph card from your agents/ tree; the skills/ copy was used, since the agents/ copy only differs in cross-links).
Both trees in qntrlworker (.claude/agents/reactor-actor-engineer and .claude/skills/reactor-actor-engineer) were identical except those cross-links, so only the skills/ copy is uploaded.

## Multica side
- Skills circuit-engineer (22 files) and reactor-actor-engineer (15 files) were re-uploaded; stale content removed. Previous live versions are saved in `history/skills-before-sync-*/`.
- Worker, Worker-1, Worker-O: step 4 now tells them to load circuit-engineer (Multica section, then one reference, scripts with CIRCUIT_REPO_ROOT) or reactor-actor-engineer (Multica section, Task -> Files map, scripts/verify.sh with REACTOR_REPO_ROOT) and that their own instructions, then AGENTS.md, win over a skill. Reviewer may load them for conventions.
- Refresh: edit `skills-src/`, then `python3 tools/sync_skills.py` (dry run) and `python3 tools/sync_skills.py --apply`. If you change the originals in `.claude/`, copy them over `skills-src/` first and re-apply the fixes listed above (or tell me and I will).
- Scripts in a Multica skill folder lose the executable bit; call them with `bash <path>`.

## 2026-10-29 (later): test report shows input / output / expected
- circuit-engineer: references/test-patterns.md has a new section "Show input, output and expected in the HTML report" (TestReporter keys input, output, expected); SKILL.md Multica section points to it.
- Not present in the original .claude files.
