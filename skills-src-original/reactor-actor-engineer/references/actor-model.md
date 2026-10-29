# Actor model (reference)

Root: `source/reactor/com/qntrl/worker/reactor/` (paths relative to this). Akka classic actors + Akka Persistence (Cassandra journal).
Verify with Read/Grep before citing line numbers; they drift.

---

## 1. Process = tree of actors

```text
Processor (AbstractProcessor, one per process)        persistenceId = actor name (processId)
  └─ top task actor "<proc>_task"  (LinearActor: top_linear)
       ├─ AbstractLinearActor      "<self>_task<idx>"   one child at a time
       ├─ AbstractParallelActor    "<self>_task<idx>"   fan-out, join on all
       ├─ AbstractBatchActor       "<self>_task<idx>"   iterate inputList, `degree` in flight
       ├─ AbstractWaitActor        leaf timer
       ├─ AbstractTaskActor        leaf (function/webhook/email/... in circuit repo)
       ├─ ProcessActor             "circuit" task: spawns a CHILD Processor named childProcessId
       └─ SequentialTask           NOT a local child: BundleMessage -> SequentialShard / supervisor
```

Children are created by name with `actorOf`; a parent re-creates a child with the same name to
resume/restart/recover it (journal replay restores the child's state).
Concrete actors (`com.qntrl.execution.*`) live in the **circuit** repo; `actor.conf` maps task `type` -> actor class + task class.

## 2. Inheritance (what each layer adds)

```text
AbstractPersistentActor
 ZRVariables    state: global(ZRGlobals), replyRef, actorData, local(ZRLocal), executionScopeData,
                isRecovered, blockActor; createReceiveRecover; setVariables/updateVariables; logger prefix
 ZRPersistence  persistenceId()=actor name; persistActorData/IOEntity/ExecutionScope; persistAndDelete*; terminate()
 ZRActor        handleBoot status machine; processActorStatus; postStop reply to parent
 ZRException    processUserException (retry -> fallback -> failure), initSchedule, initRollback
 ZRTaskActor    recoverActorState, recoverForAbort
 SystemActor    no-op retry/schedule/onActorRecover; getErrorHandlerName()=null (system actors never retry)
 ControlActor   createActor (class lookup, limits, sequential routing, dispatcher), handleResume/Restart
 ├─ FlowActor   pause/response-waiting/abort/success + resume/async id lists
 │   ├─ AbstractProcessor | AbstractLinearActor | AbstractSequentialActor | ProcessActor
 └─ PathActor   (only baseactor with createReceive) per-index PathData, resume/restart by id
     ├─ AbstractParallelActor | AbstractBatchActor
AbstractTaskActor extends ZRTaskActor        AbstractWaitActor extends SystemActor
```

`actors/baseactor/Processor.java` is a trivial concrete `AbstractProcessor`; `actors/flowactor/{Linear,Parallel,Wait}Actor`
are skeletons not referenced by `actor.conf` (real ones are in circuit).

## 3. Status machines

`config/ActorStatus` (journaled): IDLE0 SUCCESS1 RUNNING2 ABORT3 FAILURE4 CHANGE_FLOW5 TASK_RETRY6 FALLBACK7 PAUSE8
WAITING9 RESTART10(unused) RESPONSE_WAITING11 ROLLBACK12. `valueOf(int)` = `values()[i]` (out-of-range throws).
`config/ZRStatus` (SUCCESS/RUNNING/ABORT/FAILURE): aggregate result for path actors.
`config/ZRAction` (NONE/BOOT/RESUME/PAUSE/ABORT/RETRY): HBase `ProcessData`/`ResumeData.action`; recovery only picks `BOOT`.

`ZRActor.handleBoot` (BOOT message after bundle):

| Persisted status | Action |
|------------------|--------|
| IDLE | `onStart()` -> RUNNING -> `persistActorState()` -> `initActor()` |
| RUNNING / RESPONSE_WAITING | `recoverActor()` |
| TASK_RETRY | `retryActor()` |
| WAITING | `scheduleActor()` |
| PAUSE | hold; wait for RESUME |
| others (SUCCESS/FAILURE/ABORT/CHANGE_FLOW/FALLBACK/ROLLBACK) | `context.stop` -> `postStop` re-sends terminal status to parent |

`processActorStatus(status)`: SUCCESS/CHANGE_FLOW/ROLLBACK -> `onSuccess` + persist IO/scope; FAILURE -> `onFailure`;
ABORT -> `onAbort`; FALLBACK -> `onFallback`; then `terminate()` (no-op when `blockActor`).
`postStop`: sends the terminal status to `replyRef` (null `replyRef` = NPE). If `blockActor` (abort path) it instead deletes
persisted data and calls `abortActor()`; PAUSE/RESPONSE_WAITING/ABORT are only forwarded when not blocked.

## 4. Message types (`util/ReactorConstants`, carried in `ZRMessage.type`)

BOOT, SUCCESS, FAILURE, ABORT, PAUSE, RESPONSE_WAITING, RESUME, RESTART, SCHEDULE_FAILURE, PARTIAL_RESTART, PROCESS_RETRY,
TASK_RETRY, CHANGE_FLOW, FALLBACK, ROLLBACK, ABORT_RECOVER, ABORT_ACK, SELF_ABORT, ABORT_PROCESS, ABORT_ALL_PROCESS,
FETCH_ENTITY, RECEIVE_ENTITY, UPDATE_RESUME_LIST, UPDATE_ASYNC_LIST, UPDATE_PROCESS_LIST, ABORT_PROCESS_LIST, RESPONSE.
(`constants/ActorConstants` duplicates an older subset — legacy; use `ReactorConstants`.)

Non-`ZRMessage` envelopes: `ActorBundle` (state delivery, always sent BEFORE the BOOT/control message), `BundleMessage`
(sequential work), `ZRProcess` (start), `ShardEnvelope` (shard routing wrapper), `Recover*` messages, rate-limiter permits.

**Ordering rule:** every re-entry sends `ActorBundle` then the control/BOOT message to the same entity
(`ControlActor.tellBundleAndBootMessage`; sharded: two `ShardEnvelope`s).

## 5. Persistence mechanics (details: [persistence.md](persistence.md))

- `persistenceId` = `getSelf().path().name()` -> child names must be stable and unique; journal identity IS the name.
- Journaled: `ActorData` (any subclass, whole object), `IOEntity`, `ExecutionScopeData` (version-gated), `ZRGlobals` (only by `AbstractProcessor.persistGlobalData`).
- Never journaled: `ZRMessage`, `ActorBundle`, `BundleMessage`, `ZRTask`, `ZRLocal`, `replyRef`.
- `isRecovered` flips only on `ZRGlobals` or `IOEntity` replay. No `RecoveryCompleted`, no snapshots.
- `ZRTaskActor.recoverActorState`: `isRecovered` -> `updateVariables` + `onActorRecover()`; else `setVariables`; then `onActorEnter()`.
- Persist callbacks are empty (`e -> {}`); only `persistAndDelete(cb)` / `persistAndDeleteData(id)` run work after the journal ack.

## 6. Per-actor behavior cheat-sheet

| Actor | init | recover | success / failure aggregation | notes |
|-------|------|---------|-------------------------------|-------|
| `AbstractProcessor` | `updateProcessStatus(RUNNING)`; child `<self>_task` BOOT (`isInclude=true`); non-root sends `UPDATE_PROCESS_LIST` to root via `actorSelection("/user/**/<root>")` | re-BOOT child `isInclude=false`; `onActorRecover` blocks to rebuild max-version `ExecutionScopeData` from child journal | SUCCESS/ABORT delete ProcessData row + journal; FAILURE keeps row (retry). `postStop` `updateDB`+`pushLogs` | Abort protocol: ABORT_PROCESS -> ABORT_RECOVER down the chain -> ABORT_ACK up -> 5 s timer -> SELF_ABORT |
| `AbstractLinearActor` | child idx=`indexOf(start)`; `persistAndDeleteData(oldChild)` then create next | `resolveRecoveryStartIndex` skips tasks already committed in `SequentialData` (by `taskUniqueId`/name) | `TailTask` ends; CHANGE_FLOW/FALLBACK/ROLLBACK truncate list after current idx and append `taskList`; FAILURE keeps child journal | RESUME/RESTART/SCHEDULE_FAILURE re-create current child and forward |
| `AbstractParallelActor` | `execute()` creates all children (stop on first create failure) | `PathActor.recoverActor`: re-BOOT RUNNING/RESPONSE_WAITING paths | all paths terminal -> SUCCESS iff all SUCCESS else FAILURE; all PAUSE -> PAUSE | SUCCESS/ABORT path journals deleted on completion; FAILURE kept |
| `AbstractBatchActor` | `inputList=getIOEntityList()`; start `min(batchSize, degree)` | `onActorRecover` re-inits transient counters | `verifyAndContinue` keeps `degree` in flight; optional `delay` via scheduler; retry "bucket" for PROCESS_RETRY | task per item = `bindTask` |
| `AbstractWaitActor` | `initSchedule(duration, SUCCESS)`; <30 s local timer, >=30 s PAUSE + global ResumeData | restarts full duration (RUNNING recover) | RESUME with matching `resumeId` completes | no ABORT/PAUSE/FAILURE handlers |
| `AbstractTaskActor` | `initExecute()` -> `execute()` -> SUCCESS; exceptions -> `processUserException` | `recoverActor` = `initActor` (**re-executes task, at-least-once**) | RESUME(matching id) -> TASK_RETRY; RESTART(asyncId) -> `receiveActorResponse` -> SUCCESS | subclasses must not override protected lifecycle methods |
| `ProcessActor` | writes AsyncData + ProcessData(RUNNING,BOOT); spawns child Processor named childProcessId | `getProcess(childId)` + `execute()` | SUCCESS/FAILURE/ABORT clean AsyncData/ResponseData/ProcessData | adds its own resumeId/asyncId into forwarded id sets |
| `AbstractSequentialActor` | n/a (receives `BundleMessage`) | in-memory queues NOT persisted; `lastDone` reloaded from HBase | see [sequential.md](sequential.md) | skips journal via `SequentialRouter` |

## 7. Errors, retry, fallback, rollback (`ZRException`)

`processUserException(ex)`: handler name = `getErrorHandlerName(ex)` -> `task.getErrorHandler(name)`;
null/empty -> FAILURE. Else if `hasRetry && retryLimit > attempt` -> `handleRetry` (attempt++ in `ActorData.retryMap`,
delay = `delay * stepDelay^attempt` seconds, `initSchedule(duration, TASK_RETRY)`); else if `hasFallBack` -> rollback
(`FallBack.rollback`) or `changeTask` from named tasks -> FALLBACK; else FAILURE.
`initSchedule`: < 30 s -> status WAITING + `scheduleLocal` (Akka scheduler to self); >= 30 s -> `scheduleGlobal` (ResumeData row +
`sendResumeIdList` up the tree) + status PAUSE. `scheduleGlobal()` hard-codes message type RESUME.
`initRollback`: builds compensation tasks from `ExecutionScopeData.compensationStack` (LIFO), appends `FailureTask` only if non-empty,
sets status ROLLBACK (treated like SUCCESS + `changeTask`).

## 8. `ControlActor.createActor(bundle, name, message, isInclude)`

1. `ActorConfiguration.getActorConfig(task.type)` (lazy-loaded from `actor.conf`; failure -> `ACTOR_CONFIG_NOT_FOUND`, returns false, no status set).
2. `isInclude` only: `DataHelper.checkAbortRequest` (pending abort -> false); non-system actor -> `isLimitExceeded()` (`RootExecutionTaskCounter` vs `taskLimit`, **fail-closed**: any exception = exceeded -> ABORT).
3. Attach global/scope/`replyRef=self`; `persistExecutionScope()`.
4. `SequentialTask` (or adapter-supported task) -> `BundleMessage` to `SequentialShard` (`ShardEnvelope`) or supervisor; blank sequence key -> FAILURE to self.
5. Else `actorOf(Props, name)`; dispatcher: type `function` -> `function-dispatcher`; parent `isRecovered` -> `recovery-dispatcher`; else default. Tell bundle, then BOOT.
6. `InvalidActorNameException` -> only the control message is forwarded via `actorSelection(name)` (bundle is not re-sent).

`isInclude=true` = new execution (counts toward task limit, checks abort); `false` = re-entry/recovery (no re-count).

## 9. Entities & serialization

`ReactorSerializer` (id 41, Java serialization, `allow-java-serialization=off`): bound to `ZRSerializable`, `ShardEnvelope`, `ActorBundle`.
`IOEntity`/`ZRHelper` -> `secure-entity-serializer` (circuit repo). Classes that are only `Serializable` (`ZRLocal`, `CreditEntry`, `PathData`)
work only embedded inside a bound parent. `ReactorSerializer` returns **null** on any (de)serialization error (silent).
Any new message sent across nodes or journaled MUST implement `ZRSerializable` (or be bound) — otherwise remoting/persist fails.

`ActorData` hierarchy (all journaled): `ActorData`(index, resumeId, asyncId, timeStamp, handlerName, changeTask, status, abortConfig, retryMap)
-> `ControlActorData`(resumeIdList, asyncIdList) -> `PathActorData`(dataList<PathData>, pathSize, processNext; custom v1/v2 stream) -> `BatchActorData`;
`FlowActorData`(childActorName) -> `LinearActorData`(currentIndex, taskList, firstFallBackIndex), `ProcessActorData`, `ProcessorData`(processIdList);
`SequentialActorData` (empty). **Changing fields of these = journal compatibility change** (custom `readObject/writeObject` in Path/Batch/Processor data).

## 10. Task classes (`tasks/flow`)

`ZRTask<E extends ErrorHandler>`: uniqueId, name, type, input, start/endTime, errorHandlers, rollbackTask.
`LinearTask`(taskList,start) `ParallelTask`(taskList) `BatchTask`(bindTask,degree,delay,inputList) `WaitTask`(duration)
`SequentialTask`(bindTask, sequential, priority, sequenceKeyPath, outboundIntegrationKeys) `BranchTask`(conditions) `TailTask`(terminal marker).
`tasks/Task.java` is unused. Error types: `ErrorHandler`{`Retry`(retryLimit, delay, stepDelay), `FallBack`(tasks, rollback)}; `ErrorHandleable` is dead.
