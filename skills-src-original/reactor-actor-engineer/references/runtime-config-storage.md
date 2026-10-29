# Runtime, config, gRPC, storage (reference)

Root: `source/reactor/com/qntrl/worker/reactor/`. Conf: `product_package/conf/ReactorWorker/`. Verify before citing.

---

## 1. Startup (`main/ReactorWorker.java`)

Entry: `main/ReactorWorkerService.start` runs only if `worker.properties` `worker.reactor.enabled=true` (shipped `false`):
`ReactorQuery.initializeClient()` -> `StoreWrapper.initializeStore()` -> `ReactorWorker.start()` -> `BPZQCommonUtils.initReactorDeferredZQConsumers()`.

`start()`: `startAkka()` -> `startGrpc()` (thread `reactor-grpc-server`) -> status RUNNING.
`startAkka()`: resolve node (env `REACTOR_HOST` > `-Dreactor.node.host` > `hostname`, matched to `seed.nodes[].host`) -> `new ReactorQuery(node, commonKey)` ->
`loadApplicationConfig` (injects artery host/port, Cassandra contact points/auth, keyspace `new_akka`, singleton role) -> blocking `checkCassandraConnection` ->
sharded or non-sharded init -> register CoordinatedShutdown (stop gRPC on cluster leave) -> if sharded+migration, start async HBase migration.

ActorSystem name = `<reactor.akka.cluster.name>_new`. Seeds use protocol `akka` (artery).

| Step | Non-sharded (`initNonShardedActorSystem`) | Sharded (`initShardedActorSystem`) |
|------|-------------------------------------------|------------------------------------|
| Config | strips SBR (`downing-provider-class`, `split-brain-resolver`) | keeps SBR (`keep-majority`, stable-after 20 s) |
| Regions | none | `ProcessorShard` (`ActorConfiguration.getProcessorClass()`, `ProcessorMessageExtractor`), then `shardAllocationTracker`; `SequentialShard` (circuit `SequentialActor`, `priority-mailbox`, `SequentialMessageExtractor`) |
| Outbound limiter | local `/user/outboundRateLimiter` (per-node) | ClusterSingleton `outboundRateLimiterSingleton` + proxy (cluster-wide) |
| Supervisor | local `SupervisorActor` + `SupervisorPriorityMailbox` | ClusterSingleton `supervisorSingleton` (PoisonPill terminate) + proxy `supervisorProxy` (role-restricted if `singleton.role`) |
| Then | `initPersistenceAndPubSub` | `initPersistenceAndPubSub` |

`initPersistenceAndPubSub`: Cassandra read journal, `Cleanup`, async `ALTER TABLE messages default_time_to_live = max_events_time`, DistributedPubSub subscribe supervisor to topic.
`isAcceptingWork()`: status RUNNING && gRPC server up (&& self member `Up` when sharded). `registerOnMemberRemoved` -> status ABORT + stop gRPC.
`stop()`: CoordinatedShutdown 60 s then terminate; `exit-jvm=off`.

## 2. gRPC (`grpc/ReactorWorkerGrpcService.java`, proto `reactortasks.proto`, service `ReactorExecutor`)

| RPC | Maps to |
|-----|---------|
| `initProcess(ProcessJson)` | Gson -> `com.qntrl.execution.process.Process` (circuit) via `ZRTaskConvertor` -> `Reactor.initProcess` -> `service.ReactorActions.initProcess` |
| `killProcess(ProcessId)` | publish `ABORT_PROCESS` (MANUAL) |
| `retryProcess(ProcessId)` | publish `PROCESS_RETRY` |
| `killAllProcess(KillAllProcess)` | publish `ABORT_ALL_PROCESS` (`AbortConfig.ABORT_ALL`) |
| `initResponse(ResponseObject)` | `ReactorActions.initResponse` |
| `crawlIp`, `getShardStats` | local IP; `ShardStatsHelper.getLocalStats()` |

No gRPC `resumeProcess` (exists only in `Reactor`/`ReactorActions`). Admit/control RPCs return `UNAVAILABLE` when `!isAcceptingWork()`.
Security: `ReactorWorkerSecurityFilter("reactor")` + `security-reactor-grpc-api.xml` (100 req/s per user; `crawlIp` has no entry) + interceptors. Port `grpc.server.port` 3039.
Client side = `source/reactoragent` (`ReactorWorkerAgent` -> `ReactorGrpcClient`; also used by `DataHelper` to forward `initResponse` between nodes). **Out of scope** for this agent unless the reactor call site is the issue.

Service layer is `service/` (`Reactor`, `ReactorActions`, `DataHelper`). `main/ReactorActions.java` is mostly commented-out legacy
(only Cassandra journal helpers + legacy `akka.tcp://` path builders) — do not edit it expecting runtime effect.

## 3. Config levers

### `server.conf` (`config/ReactorServerConfiguration.java`)

| Key | File value | Notes |
|-----|-----------|-------|
| `reactor.sharding.enabled` | false | legacy alias `sharding.processor.enabled` honored |
| `reactor.sharding.processor.number-of-shards` | 30 | code default 10. **Never change on a live env** (shard hash = murmur3 % N) |
| `reactor.sharding.sequential.number-of-shards` | 10 | defaults to processor count if absent |
| `reactor.migration.enabled` | false | one-way cutover |
| `reactor.recovery.initial_delay` / `tick_interval` / `batch_size` / `max_in_flight_per_batch` / `fanout_stagger_ms` | 5 s / 250 ms (min 50) / 50 / 10 / 50 | `akka.actor.recovery.*` aliases exist |
| `reactor.supervisor.member_removed_reload_debounce_seconds` | 60 | also debounces mailbox-pressure reload |
| `reactor.supervisor.subscribe.topic` | `new_pub_sub_topic` | publish side hard-coded |
| `reactor.metrics.enabled` / `publish_interval` | false / 60 s | code defaults true / 10 s |
| `reactor.actor.max_execution_time` / `max_hbase_time` / `max_events_time` | 30 d / 31 d / 32 d | abort / HBase TTL / Cassandra TTL; `max_events_time` has no code default |
| `reactor.persistence.enabled` | true | gates Cassandra config + connection check only |
| `reactor.grpc.server.*` | port 3039, max_threads 100, idle 60 s | several keys unread |
| `reactor.hbase.common.user.key` | `QntrlWorker` | required even if not sharded |
| `reactor.akka.cluster.seed.nodes`, `singleton.role`, `singleton.host` | templated | |

### `application.conf` (Akka)

- Serialization: `allow-java-serialization=off`; `reactor-serializer` for `ZRSerializable`, `ShardEnvelope`, `ActorBundle`; `secure-entity-serializer` for `ZRHelper`, `IOEntity`.
- Dispatchers (`akka.actor.*`): `default-dispatcher` fork-join 40-120; `recovery-dispatcher` 4-20; `function-dispatcher` 20-80; `hbase-writer-dispatcher` fixed 32; `maintenance-dispatcher` fixed 8.
- Mailboxes: `priority-mailbox` (`PriorityMailbox`); `reactor.supervisor-priority-mailbox` (`SupervisorPriorityMailbox`, `max-capacity` 5000, `log-interval` 1000). `startAkka` fails if the latter path is missing.
- `akka.actor.sequential-actor.*`: batch-window-ms 1100, min-spacing-after-success-ms 1100, gap-wait-ms 3000, last-done-lookback-ms 3600000, max-pending-depth 0, max-throttle-retries 3, idle-timeout-ms 600000.
- `akka.actor.outbound-rate-limiter`: enabled true; default-integration-key `default`; integrations `default` & `teams-graph-chat` (1/s, burst 1, in-flight 1), `teams-graph-tenant` (45/s, burst 50, in-flight 50).
- Persistence: Cassandra journal/snapshot plugins, keyspace `new_akka`, autocreate on; journal LOCAL_QUORUM, snapshot ONE.
- Cluster: provider `cluster`; sharding `remember-entities=off`, `state-store-mode=ddata`, `rebalance-interval=100d`, passivation idle 30 min; singleton name `supervisor`; `jvm-exit-on-fatal-error=false`.

### `actor.conf`
`reactor.processor` (Processor class) + `reactor.actor.{system,circuit}` lists of `{type, actor, task}`; `types: ["system","circuit"]`. System actors (`top_linear`, `linear`, `end`, `skip`) have no state-transition accounting.
Adding a task type = add a line here **and** the actor/task classes in the **circuit** repo (not this repo). `circuit_tasks.xml` is overwritten by the build from circuit package.

## 4. Storage (HBase via ZMS meta-store, `storage/ZRStorage`, `query/ReactorQuery`)

Not direct HBase: `ReactorQuery` holds a `QueryClient`; `ZRStorage` is loaded through a JCL classloader over `lib/hbase`. Rows are keyed `(userKey, dataKey)`, values Java-serialized + index columns (defs in `product_package/conf/HBase/*.xml`).
`storeKey` = `hbase.common.user.key` when sharded, else node name.

| Entity | userKey | dataKey | Key columns / notes |
|--------|---------|---------|---------------------|
| `ProcessData` | storeKey | processId | rootProcessId ("-1" = root), action, status, scopeId, nodeName, shardId, startTime |
| `ResumeData` | storeKey | resumeId | processId, rootProcessId, time, action, messageType, asyncId, shardId |
| `SequentialData` | common key | sequentialId | sequenceKey, priority, status, startTime; also gap watermark row `gapwm:<sequenceKey>` (`lastDone` in priority col) |
| `AsyncData` | common key | processorId | circuitActorPath, parentProcessorId |
| `ResponseData` | common key | asyncId | processorId, actorId, payload, response, property=`{"userKey":node}` |
| `ExecutionLoadMetrics` | common key | executionId | batchId, circuitId, status |
| Counters | storeKey | caller key | task-limit counter (`RootExecutionTaskCounter` flush) |

Key queries: `getRecoverableRootProcesses` (RUNNING|RESPONSE_WAITING + BOOT; shard-aware index with in-memory fallback), `getPendingScheduleDueBefore`,
`forEachAbortableRootProcessByScope`, `resolveCallbackRouting` (ResponseData ⨝ AsyncData), `getGapOrderBaseline`, `upsertGapOrderWatermark`.
`SecondaryStorage` is an empty class. `ReactorWorkerConstants.java` is empty.

HBase rows (recovery/resume/process state) vs Cassandra journal (actor state) are **two separate stores** — see [persistence.md](persistence.md).

## 5. ZQ + logging

`zq/ZQListenerCallBack`: commits offset **before** `ReactorActions.initResponse` (failure = lost message). `zq/ZQProducerCallBack`: on produce failure builds error response and calls circuit `ReactorHandler.initResponse`.
Log prefix from `ZRVariables.getLoggerMessage`: `[[REACTOR_ACTOR_MESSAGE]] [scope] [root] [process] [state] [actor] ::: msg`; `ReactorLogListener` parses it (possible off-by-one on bracket index) and `ReactorLogHandler` ships to ZLogs type `reactor`. Do not change the prefix format casually.

## 6. Build

`bash build/local_build/run.sh` -> `ant -Dpdt_name=qntrlworker` (script hard-codes Linux paths; adjust ANT_HOME/JAVA_HOME locally). Reactor jars: `qntrl-worker-reactor.jar`, `qntrl-worker-reactor-store.jar` (`common/**` + `storage/**`), `qntrl-reactor-proto.jar`, `qntrl-worker-reactor-agent.jar`.
`build/ant.properties` lists akka 2.6.2 / cassandra plugin 0.103 which look stale vs the APIs used (sharding, SBR, `Cleanup`) — real runtime jars are fetched at build time; do not assume versions from it. No JUnit/TestKit suite exists.
