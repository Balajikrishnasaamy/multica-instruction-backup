# Supervisor, recovery, mailbox, maintenance, migration (reference)

Root: `source/reactor/com/qntrl/worker/reactor/`. Verify with Read/Grep before citing line numbers.

---

## 1. SupervisorActor (`actors/SupervisorActor.java`, helper: `SupervisorActorHelper.java`)

Sharded: ClusterSingleton (proxy `supervisorProxy`, manager `supervisorSingleton`). Non-sharded: one local actor per node (`<node>_new`).
Subscribed to DistributedPubSub topic `new_pub_sub_topic` (config `supervisor.subscribe.topic`; **publish side hard-codes the same constant**).

`preStart`: build helper; subscribe cluster events (MemberEvent, UnreachableMember; NOT ReachableMember); spawn `maintenance` + `metrics` children;
boot-recovery gate (below). `postStop`: unsubscribe cluster, cancel debounce timers.

### Handlers (`createReceive`)

| Message | Handler / effect |
|---------|------------------|
| `MemberUp` / `UnreachableMember` | `ShardAllocationSnapshot.unfreeze` / `freeze` |
| `MemberRemoved` | freeze, collect dead node's shards into `pendingMemberRemovedShardIds`, trailing-debounce `"RECOVER_AFTER_MEMBER_REMOVED"` |
| `"RECOVER_AFTER_MEMBER_REMOVED"` (sharded only) | defers while `coordinatorRecoveryInProgress`; empty snapshot retried up to 3x then unrestricted reload; else `reloadRecoveryCoordinator("MEMBER_REMOVED", shards)` |
| `RecoveryMailboxPressure` | debounce `RecoverAfterMailboxPressure` (reuses member-removed debounce ms) |
| `RecoverAfterMailboxPressure` (both modes) | `ensureRecoveryCoordinatorReuseFilter` (reload or create) |
| `RecoveryProgressUpdate` | sets `coordinatorRecoveryInProgress` |
| `"MIGRATION_COMPLETE:<node>"` | `handleMigrationCompleteSignal` |
| `"DELAYED_STARTUP_RECOVERY"`, `"TRIGGER_RECOVERY"` | `executeRecoveryOnce(...)`; **no sender in this repo** |
| `ZRProcess` | `handleStartProcess` (sharded: `ProcessorShardBootstrap.startFreshProcess`; non-sharded: create Processor + BOOT) |
| `ZRMessage` RESPONSE | `handleResponse` -> RESTART or PARTIAL_RESTART (via `resolveCallbackRouting(asyncId)`) |
| RESUME / RESTART / PARTIAL_RESTART / ABORT_PROCESS / PROCESS_RETRY | `handleResume/Restart/PartialRestart/Abort/ProcessRetry`: dependency check (`DataHelper.check*Dependency`) then **bundle then message** (sharded `ShardEnvelope`; non-sharded child or recreate) |
| ABORT_ALL_PROCESS | `handleAbortAll`: scan abortable roots by scope (RUNNING/RESPONSE_WAITING/PAUSE/WAITING/TASK_RETRY) -> ABORT_PROCESS each |
| SCHEDULE_FAILURE | `handleScheduleFailure` (deletes resume if routing not found) |
| PAUSE/RESPONSE_WAITING/CHANGE_FLOW/FALLBACK/UPDATE_*_LIST | log only |
| SUCCESS/FAILURE/ABORT | log + `RootExecutionTaskCounter.resetLocal(root)` |
| `ExecutionTimeAbortMessage` | `handleAbort` (from MaintenanceActor) |
| `RecoverySchedulerMessage` | dispatch resume / scheduleFailure / restart / partialRestart |
| `RecoverProcessorBatchMessage` | first `maxInFlight` immediately, rest in staggered waves (untracked timers) |
| `RecoverSingleProcessMessage` | `helper.recoverProcessor` |
| `BundleMessage` | sequential shard route, or supervisor-local SequentialActor (`priority-mailbox`, watched) |
| `matchAny` | SEVERE "unhandled" |

### Boot recovery gate

| Mode | Behavior |
|------|----------|
| Non-sharded | `ensureRecoveryCoordinator(false, "NON_SHARDED_BOOT", null)` immediately |
| Sharded, migration off | `ensureRecoveryCoordinator(true, "SHARDED_BOOT", shardedBootShardFilter())` immediately |
| Sharded, migration on | wait until `MIGRATION_COMPLETE` from **all** seed nodes, then `executeRecoveryOnce("MIGRATION_SYNC")`; **no timeout** (fail-closed) |

`executeRecoveryOnce` is guarded by `recoveryExecuted`; the immediate boot paths do not set it.
`ensureRecoveryCoordinator`: child exists + `reloadIfExists` -> reload; exists otherwise -> SKIP; absent -> create child `recoveryCoordinator` on `akka.actor.recovery-dispatcher`.
Debounce = `reactor.supervisor.member_removed_reload_debounce_seconds` (server.conf 60; code default 60000 ms), single replaceable `Cancellable`.

## 2. RecoveryCoordinatorActor (`actors/RecoveryCoordinatorActor.java`)

Messages: `StartRecovery`, `ReloadRecovery(shardIds, reuseLastFilter)`, `RecoveryTick`, `RecoveryQueueLoaded`.

1. `preStart`: schedule `StartRecovery` after `recovery.initial_delay`.
2. `loadRecoveryQueue(isReload, force, shardFilter)`: **sets `lastShardFilter` first**, skips if load in flight (`activeLoadId != 0`) or (reload && !force && work pending); loads on `hbase-writer-dispatcher`:
   - `ReactorQuery.getRecoverableRootProcesses(shardFilter)` = roots with status RUNNING or RESPONSE_WAITING and action BOOT (null filter = all, empty set = none).
   - `ReactorQuery.getPendingScheduleDueBefore(Long.MAX_VALUE, BOOT, shardFilter)` = ResumeData rows (action BOOT).
3. `onRecoveryQueueLoaded`: drops stale `loadId`; filters by shard (`RecoveryRoutingUtil.shardIdOf`), dedupes by processId; skips schedule keys already in flight.
4. `processRecoveryBatch` (tick every `recovery.tick_interval`, batch `recovery.batch_size`):
   - **Process batches** sharded -> `ProcessorShardBootstrap.recoverProcessAsync` straight to the shard region (first `max_in_flight_per_batch`, rest staggered `fanout_stagger_ms * wave`) — **bypasses the supervisor mailbox**. Non-sharded -> supervisor `RecoverProcessorBatchMessage`.
   - **Schedules** (both modes) -> `recoverScheduler`: SCHEDULE_FAILURE delayed `max(delta, 5s)`; due now -> `RecoverySchedulerMessage`; future -> `scheduleOnce(delta)`.
5. `completeRecoveryCycle`: if deferred schedule retries pending -> forced reload; else clear and notify supervisor `RecoveryProgressUpdate(false)`.
6. `initialShardFilter`: non-sharded null; sharded `bootShardFilter` else frozen-member shards else null (cold start = all rows).

## 3. Mailboxes (`mailbox/`)

### SupervisorPriorityMailbox (lower number runs first; config `reactor.supervisor-priority-mailbox`, `max-capacity` 5000, floor 100)

| P | Message |
|---|---------|
| 0 | `ZRProcess` |
| 1 | `BundleMessage` |
| 2 | control plane: `RecoveryMailboxPressure`, `RecoverAfterMailboxPressure`, `RecoveryProgressUpdate`; ZRMessage RESPONSE, ABORT_PROCESS, ABORT_ALL_PROCESS, RESUME, RESTART, PARTIAL_RESTART, PROCESS_RETRY |
| 3 | `RecoverProcessorBatchMessage`, `RecoverSingleProcessMessage` |
| 4 | `RecoverySchedulerMessage` |
| 5 | everything else (strings, cluster events, SUCCESS/FAILURE/ABORT/PAUSE/SCHEDULE_FAILURE, `ExecutionTimeAbortMessage`, ...) |

At capacity: incoming P>=3 is **dropped** and signals `RecoveryMailboxPressure` (30 s global suppression) -> debounced recovery reload.
P1/P2 evict queued P>=3; P0 can also evict queued P2; if still full P0 soft-overflows, P1/P2 are dropped (SEVERE, no reply).
Control-plane messages are deduped/coalesced (`admitControlPlane`). Because P5 counts as "recovery-class", P5 drops also trigger pressure signals.

### PriorityMailbox (`priority-mailbox`, used by SequentialActor)
`PriorityBlockingQueue` ordered by `BundleMessage.priority`; capacity from `max-capacity` or `max-pending-depth + mailbox-internal-slack(64)`;
rejected `BundleMessage` -> FAILURE reply to its `replyRef`; non-bundle messages dropped silently at `capacity + 32`.

## 4. MaintenanceActor (`actors/MaintenanceActor.java`)

Daily at 23:59:00 local (`scheduler.schedule`, no cancel in `postStop`), on `maintenance-dispatcher`:
1. **Max execution time**: for RUNNING/PAUSE/RESPONSE_WAITING roots older than `actor.max_execution_time` (30 d) with action BOOT -> `ExecutionTimeAbortMessage(ABORT_PROCESS, EXECUTION_TIME_LIMIT_EXCEED)` to supervisor.
2. **HBase TTL**: `getAllProcessByStartTime(now - actor.max_hbase_time)` (31 d) -> delete children then roots via `ReactorActions.deleteAllProcessInfo`. **No status check**.

## 5. MetricsActor
`"LOG_STATS"` every `metrics.publish_interval` (if `metrics.enabled`); logs mailbox depth/drops, member list; asks the shard region for
`GetClusterShardingStats` / `CurrentShardRegionState`; results handled in `SupervisorActorHelper.handleShardingStats/handleShardRegionState`.
`ShardAllocationTrackerActor` (every worker) polls shard stats every 15 s and freezes/unfreezes addresses in `ShardAllocationSnapshot`.

## 6. Migration (`migration/MigrationUtility.java`, driver in `main/ReactorWorker.java`)

Only when sharding on + `reactor.migration.enabled`. Per node, daemon thread `reactor-hbase-migration` (3 attempts, 5 s x attempt backoff):
copy `ProcessData`/`ResumeData` from node key -> `hbase.common.user.key`, delete legacy rows. SUCCESS/FAILURE ProcessData rows are **skipped** (left under node key).
`AsyncData`/`ResponseData`/`SequentialData` are not migrated. On success publish `MIGRATION_COMPLETE:<node>` to topic `migration-complete` after 10 s;
if all attempts fail the signal is withheld and supervisor recovery stays gated. One-way cutover: never switch sharding off afterwards.

## 7. Control plane flows (service layer -> actors)

- `ReactorActions.initProcess`: persist `ProcessData(RUNNING, BOOT)` (+ system log) -> sharded `startFreshProcess` / non-sharded tell supervisor.
- `initResponse`: parse `execution_id` = `processId:asyncId` -> update `ResponseData` -> `ZRMessage(RESPONSE)` with routing fields -> `sendAsyncMessage` (scheduled to supervisor after hard-coded 5 s) after `DataHelper.checkServerDependency` (non-sharded: may forward over gRPC to owning node and return false; null `ResponseData` -> dropped).
- `killProcess` / `retryProcess` / `resumeProcess` / `killAllProcess`: publish to pub/sub `new_pub_sub_topic` (supervisor subscribes) — not a direct tell.
- `DataHelper` dependency checks gate each control op on ProcessData status (resume: PAUSE/RUNNING/RESPONSE_WAITING; retry: FAILURE only; abort: active **root** only). `ABORT_REQUEST`/`RESUME_REQUEST`/`ABORT_CONFIG` are static in-JVM sets.
