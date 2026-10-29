---
name: reactor-actor-engineer
description: >-
  Repo-local map + engineering workflow for the qntrlworker Akka reactor.
  Routes tasks to exact files, preserves actor lifecycle (admit -> boot -> run
  -> recover -> control), and validates sharding/persistence safely without
  rescanning source/reactor/. Use for any change under source/reactor/, or when
  touching SupervisorActor, RecoveryCoordinatorActor, AbstractSequentialActor,
  AbstractProcessor, ZRVariables, sharding, gRPC, actor.conf, dispatchers,
  mailboxes, or Teams/Cliq sequential ordering.
---

# Reactor Actor Engineer

**Purpose:** file router + lifecycle map + **safe engineering workflow** for Reactor.

Classify → open mapped files → verify with Read/Grep → change only after path/behavior is clear.
Do **not** glob all of `source/reactor/` unless the map has no match.

Root: `source/reactor/com/qntrl/worker/reactor/` (paths below are relative to this).

**Out of scope: `source/reactoragent/` is a separate module — hand back to orchestrator if the task is there.**

## Working inside the Multica CirDoc squads (these rules win over anything below that conflicts)

- You work in a checkout of the **qntrlworker** repo in your workdir (`<workdir>/qntrlworker`). The MR target is fixed: `QW_KB_BRANCH`. The repository default branch (`QNTRLWORKER_STAGING`) is a different branch and is never the target.
- Git: follow your agent instructions (commit, push the review branch `agent/<worker>/<issue>-review`, push the MR branch only after Classify & Route authorizes it). The "Git / change discipline" and "Worktree/branch isolation" notes below are generic guidance, not extra permissions or prohibitions.
- There is no automated test runner for qntrlworker in Multica (`run_test.sh` is circuit only). Your HANDOFF says `SKIPPED - qntrlworker has no automated tests yet`. The static scripts below are the check you run, and the Reviewer reads your diff. Only the Reviewer deploys, with `deploy_dev.sh`.
- Scripts live in this skill folder (`scripts/`), outside the repo. Run them from inside the checkout, or set `REACTOR_REPO_ROOT=<workdir>/qntrlworker`: `REACTOR_REPO_ROOT=<checkout> bash <this skill folder>/scripts/verify.sh`. They need only plain `grep` (no ripgrep).
- Never run `ant` or `build/local_build/run.sh` yourself; the full product build is not part of the squad flow.
- Concrete execution actors (`SequentialActor`, `FailureTask`, `BranchActor`, ...) live in the **circuit** repo (`com.qntrl.execution...`), not here. If the change belongs there, say so in a BLOCKED comment so Classify & Route can re-route.
- `source/reactoragent/` is a separate module: out of scope here.

**Detail packs** (load on demand; paths below are relative to this skill folder):

| Topic | File |
|-------|------|
| End-to-end flow, routing invariants, config levers | [references/architecture.md](references/architecture.md) |
| Actor tree, inheritance, status machine, messages, createActor, errors/retry/rollback, entities | [references/actor-model.md](references/actor-model.md) |
| Supervisor handlers, recovery coordinator, mailboxes, maintenance, migration, control plane | [references/supervisor-recovery.md](references/supervisor-recovery.md) |
| Startup, gRPC, all config keys, HBase storage, build | [references/runtime-config-storage.md](references/runtime-config-storage.md) |
| Symptom → investigation | [references/debugging.md](references/debugging.md) |
| Journal / replay | [references/persistence.md](references/persistence.md) |
| Sharded vs non-sharded | [references/sharding.md](references/sharding.md) |
| Sequential ordering | [references/sequential.md](references/sequential.md) |
| Known bugs K1-K38 (optional) | [known-issues.md](known-issues.md) |
| Report template | [templates/implementation-report.md](templates/implementation-report.md) |

---

## Mental model (30 seconds)

- A process is a tree of **persistent** actors: `Processor` → top linear → linear/parallel/batch/wait/task/`ProcessActor` children. Journal identity = actor name.
- Re-entry (resume/restart/abort/recover) = parent re-creates child **by name** and sends `ActorBundle` **then** the control message.
- Two stores: **Cassandra journal** (actor state, replay) vs **HBase** (`ProcessData`/`ResumeData`/... used for recovery discovery, routing, status). Don't conflate.
- Control ops (kill/retry/resume) go via **pub/sub topic** to the supervisor; start/recover in sharded mode **bypass** the supervisor and hit `ProcessorShard` directly.
- Sequential tasks are not local children: `BundleMessage` → one actor per sequence key (`SequentialShard` or supervisor-local), no journal, HBase watermark for order.
- Sharded vs non-sharded changes routing, supervisor topology (singleton vs per-node), limiter scope, and recovery triggers. Always check both.

## Operating rules

1. **Classify** using Task → Files. Open those files first.
2. **Do not rescan** the reactor tree; Grep inside one package (`actors/`, `sharding/`, `service/`, …).
3. **Cite file:line** only after Read/Grep in this session.
4. Always evaluate **both** `reactor.sharding.enabled=true` and `false`.
5. Treat journaled types / `persistenceId` / event class names as compatibility-sensitive.
6. **Do not modify code** before identifying the affected path and expected behavior.
7. Bugs are not inlined here. For recovery / postStop / abort / actorSelection debugging, read [known-issues.md](known-issues.md) only when needed.
8. Never invent routing — follow [references/architecture.md](references/architecture.md) invariants, then verify in source.
9. Never expose secrets in prompts, output, logs, commits, or reports. Do not modify credential stores unless the TaskSpec requires it. Review skill scripts before running them.

---

## Engineering workflow

For every task:

1. Read the TaskSpec / handoff packet.
2. Classify the affected subsystem.
3. Open the mapped files from Task → Files.
4. Trace caller → callee before modifying code.
5. Identify affected lifecycle transitions ([architecture.md](references/architecture.md)).
6. Determine whether sharding is affected ([sharding.md](references/sharding.md)).
7. Determine whether persistence/journal compatibility is affected ([persistence.md](references/persistence.md)).
8. Identify existing tests covering the behavior (see Validation — often none for reactor).
9. State the suspected root cause.
10. State the proposed change.
11. Implement the smallest compatible change.
12. Run targeted validation scripts.
13. Run required broader validation when justified (`VERIFY_COMPILE=1`).
14. Inspect the final diff.
15. Report using [templates/implementation-report.md](templates/implementation-report.md).

---

## Task → files (open these first)

| Task | Open first |
|------|------------|
| Start process / admit | `service/ReactorActions.java`, `sharding/ProcessorShardBootstrap.java`, `actors/SupervisorActor.java` (`handleStartProcess`) |
| gRPC API | `grpc/ReactorWorkerGrpcService.java`, `service/Reactor.java` |
| Supervisor routing (abort/resume/restart/response/retry) | `actors/SupervisorActor.java`, `actors/SupervisorActorHelper.java` |
| Partial restart / circuit path | `actors/SupervisorActor.java` (`handlePartialRestart`) |
| BundleMessage / sequential routing | `actors/SupervisorActorHelper.java`, `actors/abstractactor/AbstractSequentialActor.java`, `entity/BundleMessage.java` |
| Sharding on/off, shard bootstrap | `main/ReactorWorker.java`, `config/ReactorServerConfiguration.java`, `sharding/*`, `sharding/ProcessorShardBootstrap.java` |
| Recovery load / batch / MemberRemoved | `actors/RecoveryCoordinatorActor.java`, `actors/SupervisorActor.java` (member-removed / mailbox-pressure handlers), `query/ReactorQuery.java` (`getRecoverableRootProcesses`) |
| Migration cutover | `migration/MigrationUtility.java`, `actors/SupervisorActor.java` (`preStart` migration gate, `executeRecoveryOnce`) |
| Processor lifecycle / postStop / DB cleanup | `actors/abstractactor/AbstractProcessor.java` |
| BOOT / status machine | `actors/baseactor/ZRActor.java` |
| Persist / terminate / SequentialRouter skip | `actors/baseactor/ZRPersistence.java`, `actors/baseactor/ZRVariables.java` |
| createActor / function dispatcher / sequential route | `actors/baseactor/ControlActor.java` |
| Abort recover | `actors/baseactor/ZRTaskActor.java`, `actors/abstractactor/AbstractProcessor.java` (`recoverForAbort`) |
| Node-local abort/resume / response forward | `service/DataHelper.java`, `service/ReactorActions.java` (`sendAsyncMessage`) |
| Sequential batch / gap-wait / rate limit / idle | `actors/abstractactor/AbstractSequentialActor.java`, `ratelimit/SequentialActorSettings.java`, `ratelimit/OutboundRateLimiter.java` |
| Mailbox priorities / pressure | `mailbox/SupervisorPriorityMailbox.java` |
| TTL / max execution time | `actors/MaintenanceActor.java` |
| Cluster/shard stats | `actors/MetricsActor.java`, `util/ShardStatsHelper.java` |
| Actor type → class mapping | `product_package/conf/ReactorWorker/actor.conf`, `config/ActorConfiguration.java` |
| Tunables | `product_package/conf/ReactorWorker/server.conf`, `product_package/conf/ReactorWorker/application.conf` |
| Linear / parallel / batch / wait / circuit child | `actors/abstractactor/AbstractLinearActor.java`, `AbstractParallelActor.java`, `AbstractBatchActor.java`, `AbstractWaitActor.java`, `actors/flowactor/ProcessActor.java` |
| Actor tree / child naming / journal identity | `actors/baseactor/ControlActor.java`, `ZRPersistence.java` (`persistenceId` = actor name), [references/actor-model.md](references/actor-model.md) |
| Retry / fallback / rollback / schedule (WAITING vs PAUSE) | `actors/baseactor/ZRException.java`, `exception/*`, `entity/ExecutionScopeData.java` |
| Task limit / execution-count abort | `actors/baseactor/ControlActor.java` (`isLimitExceeded`), `util/RootExecutionTaskCounter.java` |
| Resume / async response routing (HBase rows) | `service/ReactorActions.java` (`initResponse`), `common/ResponseData.java`, `common/AsyncData.java`, `query/ReactorQuery.java` (`resolveCallbackRouting`) |
| Child process (circuit task) | `actors/flowactor/ProcessActor.java`, `actors/abstractactor/AbstractProcessor.java` |
| Serialization / remoting of a new message | `serializer/ReactorSerializer.java`, `interfaces/ZRSerializable.java`, `application.conf` (`serialization-bindings`) |
| Rate limiter / outbound permits | `ratelimit/OutboundRateLimiter.java`, `ratelimit/Bucket.java`, `ratelimit/OutboundRateLimiterSettings.java` |
| Shard id / entity id / extractors | `sharding/RecoveryRoutingUtil.java`, `sharding/ProcessorMessageExtractor.java`, `sharding/SequentialMessageExtractor.java` |
| HBase entities / queries / indexes | `query/ReactorQuery.java`, `storage/ZRStorage.java`, `common/QueryConstants.java`, `product_package/conf/HBase/*.xml` |
| Startup / ActorSystem / cluster / singleton | `main/ReactorWorker.java`, `main/ReactorWorkerService.java`, `config/ReactorServerConfiguration.java` |
| Process admission throttling / security filter | `grpc/filter/ReactorWorkerSecurityFilter.java`, `product_package/conf/ReactorWorker/security-reactor-grpc-api.xml` |
| ZQ callbacks / logging format | `zq/*`, `logger/*`, `actors/baseactor/ZRVariables.java` (`getLoggerMessage`) |

Concrete execution actors (`com.qntrl.execution.*`) live in the **circuit** repo; this repo maps types via `actor.conf`.
Other facts: `main/ReactorActions.java` is mostly commented-out legacy — the live one is `service/ReactorActions.java`.
`actors/flowactor/{Linear,Parallel,Wait}Actor` and `tasks/Task.java` are unused skeletons.

---

## High-risk changes

Treat as compatibility-sensitive. Before changing, state: behavior change, invariants hit, proof, sharded vs non-sharded, journal/replay impact.

- journaled event types / `persistenceId` / event class names
- actor inheritance / lifecycle methods
- `SupervisorActor`, `RecoveryCoordinatorActor`, `ZRVariables`, `ZRPersistence`, `ControlActor`
- sharding routes / `SequentialRouter` / sequential persistence
- mailbox priorities / `actor.conf` / recovery + dispatcher config
- shard count / `RecoveryRoutingUtil` hash / extractors (re-maps every entity)
- `ZRSerializable` bindings, `ActorData` subclasses and their custom `readObject/writeObject`
- child actor naming (`<self>_task<idx>`, `_bind_`, processId) — it is the `persistenceId`

---

## Validation (repo-real commands)

Scanned facts: **no** JUnit/Akka TestKit reactor suite; **no** CI workflows in this checkout; HTTP `/testing` has **no** reactor apps.

| Action | Exact command |
|--------|----------------|
| Static skill verify | `bash <this skill folder>/scripts/verify.sh` (inside the checkout, or with `REACTOR_REPO_ROOT`) |
| Non-sharded static review | `bash <this skill folder>/scripts/test-nonsharded.sh` |
| Sharded static review | `bash <this skill folder>/scripts/test-sharded.sh` |
| Full product build (not run in Multica) | `bash build/local_build/run.sh` → runs `ant -Dpdt_name=qntrlworker` |
| Build via verify (not run in Multica) | `VERIFY_COMPILE=1 bash <this skill folder>/scripts/verify.sh` |
| Live metastore smoke only | `ExecutionLoadMetricsSmokeTest.run()` (needs running `ReactorWorker`) |

### Test-selection rules

| Change class | Run |
|--------------|-----|
| Small local / docs-only | `verify.sh` |
| Actor lifecycle | `verify.sh` + both mode scripts + architecture review |
| Sharding | both `test-sharded.sh` and `test-nonsharded.sh` |
| Persistence | `verify.sh` + [persistence.md](references/persistence.md) checklist; compile if types change |
| Sequential | both mode scripts + [sequential.md](references/sequential.md) |
| Recovery | both mode scripts + [debugging.md](references/debugging.md) recovery playbook |

---

## Definition of done

- [ ] root cause identified
- [ ] implementation complete (or blocked with stop reason)
- [ ] relevant tests added/updated **or** explicitly noted unavailable
- [ ] `verify.sh` passed (and compile when required)
- [ ] sharding impact evaluated (`true` and `false`)
- [ ] persistence/journal compatibility evaluated
- [ ] actor lifecycle impact considered
- [ ] final diff reviewed; no unrelated changes
- [ ] acceptance criteria mapped to evidence
- [ ] report filled from [templates/implementation-report.md](templates/implementation-report.md)

---

## Acceptance criteria discipline

`code compiles` ≠ `task complete`.

Map each acceptance criterion → evidence (file:line and/or script result) before finishing.

---

## Git / change discipline

**Before:** record branch; `git status`; do not overwrite unrelated work.  
**During:** only required files; no drive-by formatting; no large unnecessary rewrites.  
**After:** `git diff` / `git diff --check`; confirm no generated/unwanted files.

Branches and pushes: see the Multica section at the top.

---

## Stop conditions

Stop and request human / orchestrator review when:

- repository behavior contradicts this skill
- required files cannot be found
- acceptance criteria are ambiguous
- persistence compatibility cannot be established
- required validation cannot be executed
- production-impacting behavior is unclear
- a migration is required but not specified
- repeated attempts produce the same failure
- an unrelated architectural problem is discovered

---

## Output

Use [templates/implementation-report.md](templates/implementation-report.md).

Minimum always:

- status (`completed` | `blocked` | `failed`)
- summary + root cause
- files changed with reasons
- verification commands + results
- sharding / persistence / lifecycle impact
- remaining risks

Analysis mode may still include: File:Line | Severity | Fix.

## Agent graph

When running as the dedicated reactor node under an orchestrator, also follow
[agent-card.md](agent-card.md) (handoff packet, return shape, in/out of scope).
