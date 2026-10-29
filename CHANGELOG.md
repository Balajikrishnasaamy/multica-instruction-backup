# Changelog (Multica CirDoc setup)

Every change to Multica config, skills, scripts or this skill gets a line here. Snapshots are in history/.

## 2026-10-28 / 29 session
- qntrlcore repo cache: user deleted 3 case-colliding remote branches (SDP_DUMMY, HACKSAW_ISSUE_FIX, SECURITY_BUG_FIX pairs); daemon restarted, cache re-cloned. SETUP_REVIEW.html M2 marked done.
- New Multica skill `cirdoc-code-index` (code-index/SKILL.md, code-index/circuit-index.md; tools/build_index.py, tools/refresh_code_index.sh). Added to Classify & Route, Worker, Worker-1, Worker-O, Feasibility Engineer.
- Classify & Route: "Explaining the issue" section (reads only the index; Problem, Acceptance criteria, Suspected area, Tests, High-risk files). Workers: treat Suspected area as an unverified hint.
- deploy_dev.sh: accepts `Server started in ::` as the startup marker (history/deploy_dev.sh.before-marker-fix); health check uses DEV_URL, default https://balaji-6091.csez.zohocorpin.com:8443 (history/deploy_dev.sh.before-hostname-url).
- Reviewer: DEPLOY block has `manual_command`; Classify & Route quotes it on failed deploys and on TEST-OK requests.
- MR flow: GitLab push options removed (server rejects them). Workers push plainly and post MR_READY; the user opens the MR by hand with target CIRCUIT_KB_STAGING; Classify & Route verifies the pasted /merge_requests/ URL. Squad instructions updated.
- snapshot.sh no longer deletes tools/ (it copies over it), so build_index.py and refresh_code_index.sh survive.
- Local skill `multica-cirdoc` (skill/multica-cirdoc/SKILL.md, installed at ~/.claude/skills/multica-cirdoc/SKILL.md).
- Issue CIRD-26 created and run to TEST-OK; MR still to be opened by hand.

## 2026-10-29 skills sync (circuit-engineer, reactor-actor-engineer)
- Verified the .claude files of circuit and qntrlworker against origin/CIRCUIT_KB_STAGING and origin/QW_KB_BRANCH, and against the Multica skills (circuit-engineer had only SKILL.md; reactor-actor-engineer lacked 3 references and had 6 of 39 known issues).
- Fixed copies in skills-src/ (originals in skills-src-original/, list of changes in skills-src/DIFFERENCES.md); uploaded with tools/sync_skills.py (verified by re-download). Previous live versions: history/skills-before-sync-*.
- New tools/sync_skills.py.
- Worker, Worker-1, Worker-O and Reviewer instructions now point to the two skills (rewritten/ + apply.sh, snapshot history/20261029-003717).
- The .claude/ folders in ~/Cursor/circuit and ~/Cursor/qntrlworker were not modified.
- multica-cirdoc skill updated with the repo-skills sync.

## 2026-10-29 test reports show input, output and expected
- Build/qntrl/testlib/Runner.java: records TestReporter entries (input, output, expected, any other key) and, for a failed assertion, its expected/actual values; TSV grew from 7 to 10 columns (old 7-column files still read). Runner classes rebuilt.
- Build/qntrl/testlib/report.py: per-test Input / Output (got) / Expected rows in "All tests", and in the Failures section above the stack trace (expected green, got red). Values are secret-masked.
- run_test.sh unchanged. Previous files: history/Runner.java.before-io-report, report.py.before-io-report, run_test.sh.before-io-report, runner.before-io-report/.
- Verified with a demo test (one pass, one real failure on DateUtil.atStartOfMonth), with existing tests that publish nothing (ScopeNormalizerTest, 19 pass, no io tables), and with the live run_test.sh.
- Worker, Worker-1, Worker-O: tests must take TestReporter and publish input/output/expected. Reviewer: checks the report for them (non-blocking if missing).
- circuit-engineer skill: test-patterns.md section added; re-synced and verified. Snapshot history/20261029-010655.

## 2026-10-29 re-rating
- SETUP_REVIEW.html rewritten (overall 6 -> 6.5, proven in real use 3.5 -> 6, security hygiene 4.5 -> 3.5). Previous version: history/SETUP_REVIEW.before-rerating-20261029-011938.html.
- New findings recorded there: dev server holds only the last deployed commit (CIRD-27 deploy removed the CIRD-26 fix from dev); backup repo's GitHub remote is public; Worker-1 did not load circuit-engineer in 3 runs; Copilot reports no token usage.

## 2026-10-29 deploy_dev.sh: qntrlworker compile fix
- Cause: qntrlworker source (ReactorLogListener) imports com.zoho.logs.common.util.LogTypes, which the current Build/qntrl logagent.jar (Oct 28) moved to com.zoho.logs.logclient.util.LogTypes. Old Build/reactor logagent.jar still has it. Pre-existing on the base branch, not a CIRD-29 bug.
- Fix: compile-only shim jar `deploy/compat/logagent-compat.jar` (LogTypes classes from the old logagent), appended LAST to the classpath for qntrlworker only, never deployed. Added a bytecode guard: fails if any class actually uses the shim LogTypes at runtime (javac inlines the String constants, so currently it does not). Old script: history/deploy_dev.sh.before-qw-compat. Shim copy: tools/logagent-compat.jar.
- Verified: --dry-run on CIRD-29 SHA 8db03b50 compiles, 3 jars (qntrl-worker-reactor, -reactor-store, -reactor-agent), 172 classes. Real deploy NOT run yet.

## 2026-10-29 Multica -> Zoho Cliq mention notifier (built, not yet configured or running)
- New tools/cliq-notify/: relay.mjs (no dependencies, Node 22+), setup.sh, SETUP.md, test.mjs (15 checks), test-live.mjs (7 checks).
- Listens to Multica's live websocket (`inbox:new`, the event the desktop app uses), keeps only inbox items of type `mentioned` addressed to the user, and posts one Cliq message through a bot (endpoint URL or OAuth). Catch-up read of /api/inbox on start, after each reconnect and every 5 minutes; dedupe state in ~/.local/state/multica-cliq/state.json (mode 600); first start baselines existing mentions (no flood).
- Secrets live outside the repo: ~/.config/multica-cliq/secrets.env (mode 600). Multica login is read from the CLI profile at run time (re-read after a 401). All logged and sent text is secret-masked.
- Verified: real Multica reads (login, inbox, comments) with a local stand-in for Cliq; nothing was sent to Cliq. launchd plist is generated by `setup.sh --launchd` but not installed or loaded. No files were created in the real ~/.config or ~/Library.
- Next (not built): reply from Cliq through a bot message handler calling POST /api/issues/{id}/comments.
- cliq-notify: added --exchange-code (code to refresh token, saved to secrets.env), clearer --check/401/oauth errors; 19 tests pass. User's OAuth setup stopped at Zoho 'oauth_app_blocked' / 'invalid_code'.
- cliq-notify installed as launchd service com.balaji.multica-cliq (loaded 2026-10-29 09:49 IST). Tested: starts, connects live, killed process restarts under launchd with the saved state (no duplicate send). The manually started relay was stopped first.
- cliq-notify: web link removed from messages (multica.ai unreachable from this network); SETUP.md updated (webhook token, message format, restart note); service restarted to load the change.
