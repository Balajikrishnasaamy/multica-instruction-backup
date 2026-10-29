# Reactor architecture (reference)

Root: `source/reactor/com/qntrl/worker/reactor/` (paths below are relative to this).

Load this for lifecycle, inheritance, routing, config, and mailbox detail.
Verify claims with Read/Grep before citing.

---

## Canonical actor-system flow (end-to-end)

### 1) Worker bootstrap (`ReactorWorker`)

`ReactorWorker.start()` → `startAkka()` → gRPC.

- **Non-sharded** (`reactor.sharding.enabled=false`): `initNonShardedActorSystem()` strips SBR (`withoutSplitBrainResolver`), joins seeds, local outbound limiter, local `SupervisorActor`, pub/sub subscribe.
- **Sharded** (`true`): `initShardedActorSystem()` joins seeds, starts `ProcessorShard` + `SequentialShard`, outbound-limiter ClusterSingleton + supervisor singleton proxy, then persistence + mediator.

### 2) Supervisor lifecycle + boot recovery gate (`SupervisorActor`)

In `preStart()`: build `SupervisorActorHelper`, cluster subscribe, always spawn `MaintenanceActor` + `MetricsActor`.

**Boot recovery** uses `executeRecoveryOnce` → `ensureRecoveryCoordinator(...)` at most once per supervisor lifetime:

| Mode | When boot recovery starts |
|------|---------------------------|
| Non-sharded | Immediate (`NON_SHARDED_BOOT`) |
| Sharded + `migration.enabled=false` | Immediate (`SHARDED_BOOT`) |
| Sharded + `migration.enabled=true` | Deferred until all seed nodes publish `MIGRATION_COMPLETE:<node>`, then `executeRecoveryOnce("MIGRATION_SYNC")` |

### 3) Process admission (`ReactorActions.initProcess`)

1. Persist `ProcessData` with `status=RUNNING`, `action=BOOT`.
2. Sharding on: `ProcessorShardBootstrap.startFreshProcess` → `ActorBundle` + `BOOT` as `ShardEnvelope`s to `ProcessorShard` (bypasses supervisor mailbox).
3. Sharding off: tell local supervisor (`handleStartProcess`).
4. Continues through `ControlActor` / `FlowActor` / `AbstractProcessor`.

### 4) Actor creation + BOOT dispatch (`ControlActor`, `ZRActor`)

- `ControlActor.createActor(...)` resolves class via `ActorConfiguration`.
- Regular: local `actorOf` + bundle/BOOT tell.
- Sequential: `BundleMessage` → `SequentialShard` (sharded) or supervisor (non-sharded).
- `ZRActor.handleBoot()`: `IDLE`→`initActor`; `RUNNING`/`RESPONSE_WAITING`→`recoverActor`; `TASK_RETRY`→`retryActor`; `WAITING`→`scheduleActor`; `PAUSE`→hold; default→stop.

### 5) Runtime transitions (`FlowActor` / `AbstractProcessor`)

- `SUCCESS` / `FAILURE` / `ABORT` / `PAUSE` / `RESPONSE_WAITING` in flow actors.
- `AbstractProcessor` handles resume / restart / schedule-failure / process-retry / process-abort and child re-entry.

### 6) Recovery flow (`RecoveryCoordinatorActor`)

After boot gate opens: load recoverable `ProcessData` + due `ResumeData` from HBase (optional shard filter), batch, then:

- Sharded: `ProcessorShardBootstrap.recoverProcess` / `recoverProcessAsync`.
- Non-sharded: `RecoverProcessorBatchMessage` (+ schedule recovery) to supervisor.

**Reload paths (not the migration `executeRecoveryOnce` gate):**

- **MemberRemoved** (sharded only): debounced `RECOVER_AFTER_MEMBER_REMOVED` → `reloadRecoveryCoordinator` → `ensureRecoveryCoordinator` (reload existing child, or **create** if absent).
- **Mailbox pressure** (both modes): debounced `RecoverAfterMailboxPressure` → `ensureRecoveryCoordinatorReuseFilter` (same create-if-absent behavior).

Do not claim these reloads are blocked by `migration.enabled`; only the *boot* path is.

### 7) Sequential flow and ordering

See [sequential.md](sequential.md).

### 8) Response / resume / retry / abort control plane

- `ReactorActions.initResponse` → async `RESPONSE` into the processor pipeline (`sendAsyncMessage` / `DataHelper.checkServerDependency`; sharded always local).
- `resumeProcess` / `retryProcess` / `killProcess` publish on the supervisor pub/sub topic.
- Concrete handlers: `AbstractProcessor.handleAbort` / `handleResume` / `handleRestart` / `handleFailure`.

---

## Inheritance (source of behavior)

```text
ZRVariables → ZRPersistence → ZRActor → ZRException → ZRTaskActor
  → SystemActor → ControlActor
       → FlowActor → AbstractProcessor | AbstractLinearActor | AbstractSequentialActor | ProcessActor
       → PathActor → AbstractParallelActor | AbstractBatchActor
  AbstractWaitActor extends SystemActor
```

`ControlActor` extends `SystemActor` (not a sibling).

---

## Routing invariants (do not invent)

- Sharded start: `ReactorActions.initProcess` → `ProcessorShardBootstrap` (bundle + BOOT envelopes).
- Non-sharded start: supervisor `handleStartProcess` → local `actorOf` + BOOT.
- Sharded abort / resume / retry / partial restart: **bundle then message** via `ShardEnvelope`.
- Non-sharded abort after pause/wait: recreate processor + bundle (same pattern as resume).
- `BundleMessage`: `SequentialShard` when sharding on; supervisor-local when off.
- Recoverable roots: `RUNNING` or `RESPONSE_WAITING` + `BOOT` (`ReactorQuery.getRecoverableRootProcesses`).

---

## Config levers (real paths)

`product_package/conf/ReactorWorker/server.conf`:

- `reactor.sharding.enabled` (+ processor / sequential shard counts)
- `reactor.recovery.*` (`initial_delay`, `tick_interval`, `batch_size`, …)
- `reactor.supervisor.member_removed_reload_debounce_seconds`
- `reactor.migration.enabled`
- `reactor.metrics.*`

`product_package/conf/ReactorWorker/application.conf`:

- `akka.actor.recovery-dispatcher`, `function-dispatcher`, `hbase-writer-dispatcher`, `maintenance-dispatcher`
- `akka.actor.sequential-actor.*` (`batch-window-ms`, `gap-wait-ms`, `min-spacing-after-success-ms`, `idle-timeout-ms`, …)
- `akka.actor.outbound-rate-limiter.*`
- supervisor priority mailbox under `mailboxes` / `supervisor-priority-mailbox`

Defaults checked in-repo (Oct 2026 scan):

- `reactor.sharding.enabled: false`
- `reactor.migration.enabled: false`
- processor shards: `30`, sequential shards: `10`

---

## Mailbox priorities (supervisor)

See javadoc in `mailbox/SupervisorPriorityMailbox.java`:  
0 `ZRProcess` → 1 `BundleMessage` → 2 control-plane + RESPONSE/ABORT_PROCESS/ABORT_ALL_PROCESS/RESUME/RESTART/PARTIAL_RESTART/PROCESS_RETRY → 3 recover batch/single → 4 recovery schedule → 5 other (incl. SUCCESS/FAILURE/ABORT status messages).
Full table + drop/eviction rules: [supervisor-recovery.md](supervisor-recovery.md).

More depth: [actor-model.md](actor-model.md) (tree, status machine, errors), [supervisor-recovery.md](supervisor-recovery.md), [runtime-config-storage.md](runtime-config-storage.md).
