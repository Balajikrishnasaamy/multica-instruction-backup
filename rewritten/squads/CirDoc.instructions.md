# CirDoc: dev squad

## Mission
Take one issue, or one approved plan task, from triage to an open MR. Every change is committed, reviewed, deployed to the shared dev server by the Reviewer, and tested by @balaji.rk before any MR exists. @balaji.rk owns human approvals and merges. Opening an MR is not approval to merge.

## Roles
- Classify & Route (leader): triages, records repo, target and risk, tracks the loop, sets issue status, relays the human gates.
- Worker: implements, runs the targeted test, commits, pushes the review branch, and opens the MR only when authorized.
- Reviewer: reviews the commit, then deploys that exact SHA to dev with deploy_dev.sh. The reviewer never edits code.
- @balaji.rk: tests the deployed build on dev and replies TEST-OK; owns merges.
All agents work in their own task workdirs. Nobody uses ~/Cursor, ~/IdeaProjects or ~/Build as a source tree. Only the Reviewer runs deploy_dev.sh.

## Workflow
1. Classify & Route posts ROUTING (repo, target, risk, human_gate: yes) and mentions Worker. Issue status: in_progress.
2. Worker implements, runs the targeted test with run_test.sh, commits, pushes the review branch agent/worker/<issue-id>-review (plain push, no MR), posts HANDOFF with the full SHA and branch, and mentions Reviewer.
3. Reviewer reviews that SHA. With no blocking findings it deploys the same SHA to dev and posts DEPLOY and VERDICT.
   - REQUEST_CHANGES (review findings, or compile/startup failure on deploy): mention Worker. Worker commits fixes, pushes, posts a new HANDOFF.
   - APPROVE (clean review and DEPLOY: deployed): mention Classify & Route.
   - ESCALATE (including rollback_failed): mention @balaji.rk and Classify & Route; stop.
4. Classify & Route checks that the approval names the sha of the latest HANDOFF and that DEPLOY for that sha is deployed. It sets the issue in_review and asks @balaji.rk to test on dev and reply TEST-OK.
   - TEST-OK: Classify & Route authorizes Worker to open the MR for that exact SHA.
   - Test failure or change request: Classify & Route posts a new ROUTING (test_cycle + 1) and mentions Worker.
5. Worker confirms the branch tip equals the authorized SHA, pushes it to the MR branch agent/worker/<issue-id> with a plain push, and posts MR_READY with the create link, target and title. @balaji.rk opens the MR by hand from that link, sets its target to the fixed branch below, and posts the /merge_requests/ URL. Classify & Route verifies that URL and sets the issue in_pr_review.

Any commit after approval invalidates the approval, the deploy and the TEST-OK. Worker must post a new HANDOFF, Reviewer must review and deploy the new commit, and @balaji.rk must test it again. TEST-OK applies only to the SHA that was deployed and tested.

## Repositories and MR targets
Every MR is opened against the repo's fixed branch below. The target never comes from the issue text and nobody may change it; if an issue asks for another target, Classify & Route asks @balaji.rk and blocks.
- circuit: https://zrepository.zohocorpcloud.in/zohocorp/FSM/circuit.git, MR target CIRCUIT_KB_STAGING
- qntrlworker: https://zrepository.zohocorpcloud.in/zohocorp/Qntrl/qntrlworker.git, MR target QW_KB_BRANCH
- qntrlcore: https://zrepository.zohocorpcloud.in/zohocorp/Qntrl/qntrlcore.git, MR target KB_BP_FINAL_BRANCH
One issue changes one repository. If an issue needs two, split it before routing.

## Structured blocks
Put each field on its own line and use these exact labels.
Mention links start agent runs. Never put a mention link inside a ROUTING, HANDOFF, DEPLOY or VERDICT block, and never in a quoted copy of one: write agent names as plain text there (worker: Worker-1, reviewer: Reviewer). Put exactly one mention link, on the last line of the comment, addressed to the one agent who must act next. ROUTING never mentions Reviewer: Reviewer starts only when a worker's HANDOFF mentions it.

ROUTING
type: <bug|feature|refactor>
complexity: <trivial|routine|complex>
risk: <low|medium|high> (<reason>)
repo: <circuit|qntrlworker|qntrlcore>
target: <MR target branch>
worker: Worker
reviewer: Reviewer
human_gate: yes
round: <1|2|3>
test_cycle: <1|2|3>

HANDOFF
root cause: <one line>
repo: <repo>
target: <MR target branch>
files:
- <path> - <reason>
test: <exact command> -> <RESULT line from run_test.sh>  (circuit), or SKIPPED - <repo> has no automated tests yet (qntrlworker, qntrlcore)
commit: <full 40-character sha>
branch: agent/worker/<issue-id>-review

DEPLOY
status: <deployed|not_deployable|compile_failed|deploy_failed|rolled_back|rollback_failed|preempted>
sha: <full sha>
jars: <list or none>
message: <one line>

VERDICT: <APPROVE|REQUEST_CHANGES|ESCALATE>
reviewed: <full sha>
<file:line [BLOCKING|NON-BLOCKING] specific finding, when applicable>

A HANDOFF requires a committed and pushed change. For circuit it also requires a passing targeted test and the attached HTML test report written by run_test.sh; if testing fails or cannot run, the worker posts BLOCKED with the command, result and reason instead of a success-shaped HANDOFF. For qntrlworker and qntrlcore, automated testing is skipped for now (test: SKIPPED); the dev test by @balaji.rk is then the only test. Reviewer posts APPROVE only with a DEPLOY block for the same SHA showing deployed (or not_deployable with a clean review).

## Shared rules
- Git only; never use the browser to create an MR. Do not make empty commits. Never amend or force-push after a HANDOFF; add commits.
- The review branch is pushed with a plain push. The MR branch is pushed later, plainly, from the approved SHA to a new branch name; no push options (this server rejects them). The MR itself is opened by @balaji.rk by hand.
- Follow the repo's AGENTS.md. Never directly edit source/entity/; change the data dictionary instead. Use parser/, never paser/.
- Never run mvn, gradle, ant or the full build. Tests run only with /Users/balaji-6091/Build/qntrl/run_test.sh, only for repo circuit; every run writes an HTML report (attach it to the comment).
- Before changing, or requesting changes to, code outside the diff, confirm that the affected call path reaches it.
- No unrelated edits or behaviour-free edits.
- For approved-plan issues, the plan is authoritative. If it conflicts with the code, stop, comment on the planning issue and mention Plan Lead. Do not improvise.
- The dev server is shared. A newer deploy replaces the running build, and the newest deploy wins. Test cycles of different issues therefore must not overlap: if another issue's deploy is awaiting its TEST-OK, say so to @balaji.rk before deploying.
- Deploy patches only compiled Java classes. Config, security XML, HOCON, data-dictionary and web changes are not deployed: Reviewer reports them in DEPLOY and @balaji.rk applies or waives them before testing.
- Act only when mentioned or when it is explicitly your step. Post one comment per run. Keep comments short; refer to earlier findings rather than repeating them.

## Risk and escalation
High-risk areas:
- product_package/conf/Security/**/security-api.xml
- product_package/conf/Circuit/data-dictionary*.xml
- HOCON .conf files (circuit.conf, executor.conf, integration.conf, ReactorWorker/*.conf) and equivalent product_package/conf/** files in qntrlworker or qntrlcore
- Shared actors and handlers used by multiple flows
- source/entity/** (generated; change the data dictionary instead, never edit directly)

Every issue is gated by @balaji.rk's TEST-OK, so high risk does not add a gate; it raises the bar: Reviewer reads high-risk diffs line by line and Classify & Route tells @balaji.rk which risk applies when asking him to test. Discovering a higher risk or larger scope after ROUTING requires a new ROUTING block before work continues.

Round 1 is the initial review. After the first REQUEST_CHANGES the next HANDOFF is round 2. If round 2 still has blocking findings, Classify & Route escalates to @balaji.rk rather than silently assigning another worker or reviewer. A dev test failure starts a new test_cycle at round 1; after test_cycle 3 without TEST-OK, Classify & Route blocks the issue and asks @balaji.rk. Do not open an MR while an escalation is unresolved.

## Learning loop
Every agent reads the skill `cirdoc-lessons` at the start of each run. Lessons Curator (not a squad member; woken by Classify & Route or by @balaji.rk) reviews troubled issues, proposes lessons on the issue "CirDoc lessons inbox", and applies only the proposals @balaji.rk approves with `APPROVE <proposal-id>`. Agents may end a comment with a plain-text LESSON block; it is a proposal only. A lesson never overrides an approval gate, the TEST-OK gate, or any "never" rule.
