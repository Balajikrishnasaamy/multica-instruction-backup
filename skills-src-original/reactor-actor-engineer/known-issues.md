---
# Optional companion for reactor-actor-engineer
# Read only when the task touches recovery, postStop, abort, actorSelection,
# mailbox, sequential, or the user asks about known bugs. Do not load for routine routing/edits.
---

# Known issues (verify before citing)

Status drifts. Confirm with Read/Grep on the listed files before treating as open.
K1-K6 are older entries; K7+ come from a full-repo read (Oct 2026) and were mostly code-read, not run.

## Recovery / lifecycle

| ID | Topic | Where to verify | Note |
|----|--------|-----------------|------|
| K1 | FALLBACK / CHANGE_FLOW skip DB cleanup in processor `postStop` | `AbstractProcessor.postStop` | `default: break` — no `updateDB`. Zombie rows left `RUNNING` can be recovered later. |
| K2 | Silent async drop (non-sharded) | `DataHelper.checkServerDependency`, `ReactorActions.sendAsyncMessage` | Exception / null `responseData` → `false` → no schedule. Sharded path returns `true` early. |
| K3 | `onActorRecover` no-op | `SystemActor`, `AbstractTaskActor` | `ControlActor` inherits stub; some subclasses override (e.g. batch). |
| K4 | Wildcard `actorSelection` for process-id updates | `AbstractProcessor.sendProcessIdUpdate` / `removeProcessIdUpdate` | Path `/user/**/{rootProcessId}`. Sharded entities live under `/system/sharding`; prefer stored refs. |
| K5 | MemberRemoved + recover BOOT vs live shard entities | `SupervisorActor` (member-removed), `RecoveryCoordinatorActor`, `ProcessorShardBootstrap.recoverProcess` | Sharded-only debounced reload; can **create** coordinator if absent. Recoverable = RUNNING/RESPONSE_WAITING only. Re-verify double-BOOT risk. Non-sharded mailbox-pressure reload also re-BOOTs live RUNNING children (`SupervisorActorHelper.recoverProcessor`). |
| K6 | Abort on incomplete entity | `ZRTaskActor.recoverForAbort` | Prefer null-`global` / missing journal over null `actorData` (ctor always creates ActorData). |
| K7 | `lastShardFilter` overwritten on skipped reload | `RecoveryCoordinatorActor.loadRecoveryQueue` | Line sets filter before skip checks; supervisor already cleared `pendingMemberRemovedShardIds` → shard-specific reload can be lost. |
| K8 | Priority-5 messages treated as droppable "recovery" class | `SupervisorPriorityMailbox` (`incomingPriority >= 3`) | At capacity SUCCESS/FAILURE/ABORT/PAUSE/SCHEDULE_FAILURE/`ExecutionTimeAbortMessage`/MemberRemoved/strings can be dropped and trigger pressure signal. P1/P2 drops are SEVERE with no reply. |
| K9 | Unfreeze only on `MemberUp` | `SupervisorActor` (no `ReachableMember`), `ShardAllocationSnapshot` | Reachable-again node stays frozen; included in later `shardsOfFrozenMembers()`. |
| K10 | Migration gate has no timeout/replay | `SupervisorActor.handleMigrationCompleteSignal` | Unfinished seed node blocks boot recovery forever; pub/sub signals are not replayed to late subscribers. `DELAYED_STARTUP_RECOVERY` / `TRIGGER_RECOVERY` have no sender. |
| K11 | Maintenance schedulers never cancelled | `MaintenanceActor`, `MetricsActor` | `scheduler.schedule` without `postStop` cancel → duplicates on actor restart. TTL cleanup ignores status. |
| K12 | `recoverProcess` ignores `ZRGlobals` | `ProcessorShardBootstrap.recoverProcess` | Bundle has only `replyRef`; relies on entity journal replay (`ZRGlobals` journaled only by `AbstractProcessor.persistGlobalData`). |

## Actors / tasks

| ID | Topic | Where to verify | Note |
|----|--------|-----------------|------|
| K13 | Inverted-looking `scheduleActor` comparison | `AbstractTaskActor.scheduleActor`, `ProcessActor.scheduleActor` (`timeStamp >= now` → `retryActor`) vs `AbstractWaitActor` (`<=`) | Verify intended semantics before touching. |
| K14 | Batch `initActor` continues after failure | `AbstractBatchActor.initActor` | catch → `persistAndProcessStatus(FAILURE)` then `execute()` still runs (null `inputList`). |
| K15 | Batch delay creates actor off actor thread | `AbstractBatchActor` (`scheduleOnce(... this::createActor ...)`) | `context.actorOf` + state access from scheduler callback. |
| K16 | Parallel edge cases | `AbstractParallelActor.execute/isCompleted` | Empty `taskList` never completes; failed first create gives `pause == total == 0` → PAUSE branch; abort-only reports FAILURE. |
| K17 | RESPONSE_WAITING dropped in aggregators | `AbstractParallelActor`, `AbstractBatchActor.isCompleted`, `ProcessActor.createReceive` | Not counted / not routed. |
| K18 | Long retry loses TASK_RETRY type | `ZRException.initSchedule` → `scheduleGlobal()` | Hard-codes RESUME for delays ≥ 30 s. |
| K19 | Wrong dispatcher criterion | `ControlActor.createActor` | Uses parent's `isRecovered`, not child's. |
| K20 | Name collision loses bundle | `ControlActor.createActor` (`InvalidActorNameException`) | Only control message forwarded via `actorSelection`; task counter already incremented. |
| K21 | `SequentialRouter` skip is partial | `ZRPersistence` | `persistActorData`/`persistIOEntity` skip; `persistExecutionScope`, `persistAndDelete*` do not. |
| K22 | Adapter bundle drops scope | `ControlActor.copyBundleWithTask` | `executionScopeData` not copied for adapter-wrapped sequential tasks. |
| K23 | `AbstractProcessor.initActor` / Linear ignore `createActor` false | `AbstractProcessor.initActor`, `AbstractLinearActor.createChildActor` | Abort-request / missing config → nothing signals completion. |
| K24 | `reconstructExecutionScope` blocks | `AbstractProcessor.onActorRecover` | `.get()` without timeout on read-journal stream; new materializer each recovery. |
| K25 | Out-of-range enum lookup | `ActorStatus.valueOf(int)`, `ZRAction.valueOf(int)` | `values()[i]` throws; `orElse` unreachable. `AbortConfig` is a mutable enum (shared global state). |
| K26 | `ReactorSerializer` swallows errors | `serializer/ReactorSerializer` | Returns null on any failure → silent null payloads; no deserialization allow-list. |
| K27 | `isLimitExceeded` is fail-closed | `ControlActor.isLimitExceeded` | Any exception (e.g. counter read) aborts the process. |

## Sequential / rate limit

| ID | Topic | Where to verify | Note |
|----|--------|-----------------|------|
| K28 | Gap holes not persisted; best-effort order | `AbstractSequentialActor`, `ReactorQuery.getGapOrderBaseline` | Holes written as `""`; late lower seq runs after `lastDone` jumped. |
| K29 | Throttle detection by substring | `AbstractSequentialActor.isOutboundRateLimited` | `message.contains("429")` matches unrelated text. |
| K30 | Limiter buckets never evicted; config throws | `OutboundRateLimiter`, `Bucket.fromConfig` | One bucket per distinct key (chat id). |
| K31 | `statusCodeFor` maps unknown type to SUCCESS | `AbstractSequentialActor.updateSequentialData` | "Other" responses recorded SUCCESS without advancing `lastDone`. |

## Service / gRPC / storage

| ID | Topic | Where to verify | Note |
|----|--------|-----------------|------|
| K32 | `crawlIp` double reply | `ReactorWorkerGrpcService.crawlIp` | `onError` then falls through to `onNext/onCompleted`. |
| K33 | `initResponse` silent success | `ReactorActions.initResponse`, `ReactorWorkerGrpcService.initResponse` | Missing `ResponseData` only logged, RPC still OK; gRPC layer requires `event`, service supports `meta_data.execution_id`. |
| K34 | Hard-coded 5 s delay + topic constant | `ReactorActions.sendAsyncMessage`, `ReactorConstants.NEW_PUB_SUB_TOPIC` | Publish topic ignores config `supervisor.subscribe.topic`. |
| K35 | `ZQListenerCallBack` commits before processing | `zq/ZQListenerCallBack` | Failed record lost. |
| K36 | Sharded bulk delete by nodeName | `ZRStorage.deleteAllProcess/deleteAllResume` | Matches `nodeName` index with userKey; wrong key in sharded mode (affects `flushAllData`). |
| K37 | gRPC start failure silent | `ReactorWorker.start/startGrpc` | Status RUNNING but `grpcServer` null → `isAcceptingWork()` false forever. |
| K38 | Config default mismatches | `ReactorServerConfiguration` vs `server.conf` | metrics enabled/interval, shard count (10 vs 30). |

## Not in this list

- Migration skip of SUCCESS/FAILURE lives in `MigrationUtility`, not the recovery coordinator loop.
- Mailbox priority numbers and PARTIAL_RESTART bundle-first behavior: use live `SupervisorActor` / `SupervisorPriorityMailbox`.
- `main/ReactorActions.java` is mostly dead code; do not treat its commented methods as live.

## Industry smells (when improving, not auto-bugs)

Mutable messages, `try actorOf catch InvalidActorNameException`, string `actorSelection`, node-local `DataHelper` sets, blocking DB/gRPC on actor threads, DB work in `postStop`, no explicit `supervisorStrategy`, no actor-level snapshots, `SEVERE` used for info logs (`ProcessActor`, `ZQListenerCallBack`). Confirm each before proposing a fix.
