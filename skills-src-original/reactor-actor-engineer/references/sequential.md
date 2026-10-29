# Sequential ordering (reference)

Primary files:

- `actors/abstractactor/AbstractSequentialActor.java` (ASA, ~1576 lines; extends `FlowActor`, implements `SequentialRouter`)
- `actors/baseactor/ControlActor.java` (`tellSequentialBundle`, sequence-key / priority resolution)
- `actors/baseactor/ZRPersistence.java` (`SequentialRouter` skip)
- `entity/BundleMessage.java`, `tasks/flow/SequentialTask.java`
- `ratelimit/SequentialActorSettings.java`, `ratelimit/OutboundRateLimiter.java`, `ratelimit/Bucket.java`
- `mailbox/PriorityMailbox.java`, `common/SequentialData.java`, `query/ReactorQuery.java` (gap watermark), `query/GapOrderHoleCodec.java`
- `product_package/conf/ReactorWorker/application.conf` -> `akka.actor.sequential-actor.*`, `akka.actor.outbound-rate-limiter.*`

Concrete `SequentialActor` is in the circuit repo (`com.qntrl.execution.actor.control.SequentialActor`, referenced by `ReactorWorker`).
One actor instance per **sequence key** (= `BundleMessage.actorName`), e.g. a Teams chat/channel.

---

## Flow

1. `ControlActor` sees a `SequentialTask` (or adapter-supported task) -> resolves `sequence_key` (literal or `$path` into IOContext), `priority` (conversation seq, number or `$path`), `outboundIntegrationKeys` -> `tellSequentialBundle`.
2. Sharded: `ShardEnvelope(sequenceKey, BundleMessage)` -> `SequentialShard` (`SequentialMessageExtractor`: entityId = actorName). Non-sharded: tell supervisor -> supervisor-local SequentialActor (`priority-mailbox`, watched).
3. Blank key or region not ready -> FAILURE `ZRMessage` to the sender actor.
4. ASA accepts the bundle (batch window / bypass), orders it, runs the `bindTask` in a fresh child, replies SUCCESS/FAILURE/ABORT to the original sender (`replyRef`).

## Ordering model

- Ordered queue: `NavigableMap<Long, Queue<PendingMessage>>` (TreeMap) keyed by `priority`, ascending; duplicates of one seq are FIFO. `priority <= 0` -> `legacyProcessingQueue` (FIFO, bypasses gap logic).
- `lastDoneSeq` watermark; `expected = lastDone + 1`.
  - `minSeq <= expected` -> run now (`minSeq < expected` logged "Late seq" and still runs).
  - `minSeq > expected` -> gap: legacy message may run first; else start `gapWaitMs` timer (`awaitingGapFill`); on `GapWaitTimeout` accept the hole and run `minSeq` ("Gap accept").
  - gap-wait disabled (`gap-wait-ms <= 0`) -> run lowest immediately.
- `acceptHole=true` is passed after hard FAILURE, ABORT, exception with no reply target, failed FSM exit.
- Ordering is **best effort across gap-wait timeouts/failures**: `lastDone` jumps to the completed seq; a lower seq arriving later runs "late". Holes are never persisted (`""` written; `getHoles()` unused).
- Single in-flight visit (`isBindBusy()`): child map non-empty, permit wait, in-flight pending, or throttle retry.

## ASA messages

`BundleMessage`, `DrainBatch`, `ThrottleRetryMessage`, `SpacingPollNext`, `GapWaitTimeout`, `LastDoneLoaded`, `StorageWriteDone`, `ZRMessage` (bind-child reply), `Terminated`, `PermitGranted`, `PermitDenied`, `RetryOutboundPermit`, `ReceiveTimeout`.

- **Batch window**: new bundle during no-bypass state goes to `pendingBatch`; first arrival schedules `DrainBatch` after `batch-window-ms`; drain enqueues all so ordering inside a window is by seq. Bypass (gap-wait, bind busy, lastDone loading, spacing active, queue non-empty) enqueues directly.
- **Depth guard**: `max-pending-depth > 0` and exceeded -> FAILURE "pending depth exceeded" (no `actorExp` change). Mailbox itself also rejects at capacity (`PriorityMailbox`).
- **Cold start**: `ensureLastDoneLoaded` lazily (only when ordered work exists) runs `ReactorQuery.getGapOrderBaseline(sequenceKey, lookbackMs, 0)` on `hbase-writer-dispatcher`: row `gapwm:{key}` first, else scan SUCCESS `SequentialData` within `last-done-lookback-ms`. Posts `LastDoneLoaded`.
- **Run**: `beginProcessBundleMessage` -> resolve integration keys -> (limiter on) acquire permits -> `tryRunBindChild` (validates `SequentialTask.bindTask`, FSM enter once) -> `runBindChild`: discard old child (delete journal), spawn child `{self}_bind_{taskType}_{millis}` (timestamped to avoid reusing a recovered prior SUCCESS), add RUNNING `SequentialData` row, tell bundle + message.
- **Reply handling**: always deletes child journal + releases permits; SUCCESS -> update row, FSM exit, `recordCompletion` + `persistGapOrderWatermark`, reply, schedule next after `min-spacing-after-success-ms` (minus elapsed). FAILURE -> if rate limited (message flag, "429"/"too many requests" in text, or response statusCode 429) retry with backoff up to `max-throttle-retries`, else reply failure and poll with `acceptHole`. ABORT -> reply ABORT, poll with `acceptHole`.
- **Throttle backoff**: `base = outboundRetryAfterMillis or 1000`; `+ jitter[0, min(250, base/4))`, `+50`, cap 60 000 ms. Bind lock stays closed during backoff; passivation blocked.
- **Writes**: `SequentialData` add/update/watermark are chained on `lastSequentialDataAdd` (single ordered chain on the HBase writer executor); failures are logged and swallowed.
- **Passivation**: `idle-timeout-ms` -> Akka `receiveTimeout`; stops only when no pending writes, queue empty, bind idle and all timers inactive. In-memory queues are **not** persisted; parent/shard recreates the actor on next message. Work queued but unprocessed at crash is lost unless re-sent upstream.

## OutboundRateLimiter (`ratelimit/`)

- Hosting: ClusterSingleton when sharded (cluster-wide rates); local `/user/outboundRateLimiter` when non-sharded (per-node rates).
- Protocol (all `ZRSerializable`): `AcquirePermit(s)` -> `PermitGranted(keys)` | `PermitDenied(retryAfterMillis)`; `ReleasePermit(s)`. Multi-key acquire is all-or-nothing with rollback.
- `Bucket`: token bucket (`permits-per-second`, `burst`) **plus** `max-in-flight`; `releaseInFlight` frees in-flight only (tokens are not refunded). Deny reasons: in-flight cap, no token. Retry estimate clamped 10..5000 ms.
- Key resolution: exact key (escaped) -> prefix before first `:` -> `default-integration-key` -> `default` -> limiter root. Missing numeric keys throw `ConfigException`. Buckets are created lazily and **never evicted** (one per chat id).
- Gate on `akka.actor.outbound-rate-limiter.enabled`; if enabled but limiter ref missing, ASA bypasses with a one-time warning.
- `entity/CreditEntry` is **not** part of this (it is the per-actor credit-cost ledger in `ExecutionScopeData`).

## Config keys (`akka.actor.sequential-actor`; in-repo values / code default)

| Key | In-repo | Code default | Role |
|-----|---------|--------------|------|
| `batch-window-ms` | 1100 | 0 | Batch window |
| `min-spacing-after-success-ms` | 1100 | 0 | Min interval after SUCCESS |
| `gap-wait-ms` | 3000 | 3000 (missing key); <0 -> 0; 0 disables | Wait for missing `lastDone+1` |
| `last-done-lookback-ms` | 3600000 | 3600000; 0 skips scan | Cold-start scan window |
| `max-pending-depth` | 0 | 0 (unlimited) | Queue depth cap |
| `max-throttle-retries` | 3 | unlimited if missing/<=0 | HTTP throttle retries |
| `idle-timeout-ms` | 600000 | 0 (disabled) | Idle stop |
| `mailbox-internal-slack` | unset | 64 | Added to depth for mailbox capacity |

## Ordering failure checklist

Symptom: sequential executions run out of order / stall / duplicate.

Check in order:

1. `ControlActor` key + priority resolution (`sequenceKeyPath`, `priority` `$path`; null path = NPE)
2. Shard routing (`SequentialShard` entityId = actorName vs supervisor-local); non-sharded multi-node = different supervisors?
3. `AbstractSequentialActor` queue selection (`priority <= 0` legacy FIFO skips ordering)
4. `lastDone` watermark: `gapwm:` row + SUCCESS `SequentialData` within lookback (cold start after idle stop)
5. gap-wait / `acceptHole` paths (hole accepted after timeout or failure -> late seq runs out of order by design)
6. `SequentialRouter` / journal skip (`persistExecutionScope`, `persistAndDelete*` still persist for routers)
7. Throttle retry / outbound limiter (blocking vs reordering; `awaitingThrottleRetry`)
8. Mailbox rejection (`PriorityMailbox` capacity, `max-pending-depth`) -> FAILURE replies
9. Idle passivation lost queued work
