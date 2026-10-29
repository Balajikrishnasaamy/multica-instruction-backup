# Debugging playbooks (reference)

Point at mapped files from SKILL Task → Files. Do not rescan all of `source/reactor/`.
For recovery / postStop / abort / actorSelection smells, also read [../known-issues.md](../known-issues.md).

---

## Actor creation failure

```text
Symptom:
Actor cannot be created/spawned.

Check in order:
1. ControlActor (createActor / SequentialTask route)
2. ActorConfiguration
3. product_package/conf/ReactorWorker/actor.conf
4. dispatcher configuration (application.conf)
5. mailbox configuration
6. sharding path (ProcessorShard / SequentialShard vs local actorOf)
7. ZRActor BOOT / status machine
8. resource/concurrency constraints (grpc threadpool, rate limiter)
```

---

## Recovery failure

```text
Symptom:
Process does not recover.

Check in order:
1. SupervisorActor recovery gate (executeRecoveryOnce / migration)
2. RecoveryCoordinatorActor
3. ReactorQuery.getRecoverableRootProcesses (RUNNING | RESPONSE_WAITING + BOOT)
4. HBase persistence data (ProcessData / ResumeData)
5. recovery-dispatcher
6. mailbox pressure reload path
7. sharding mode (ProcessorShardBootstrap.recoverProcess vs supervisor batch)
8. migration gate (boot only)
9. MemberRemoved reload (sharded only)
```

---

## Sequential ordering failure

See [sequential.md](sequential.md) checklist.

---

## Persistence / replay failure

See [persistence.md](persistence.md) checklist.

---

## Process start / admission failure

```text
Symptom:
Process never boots / never reaches actor.

Check in order:
1. ReactorActions.initProcess
2. ProcessData persist (status=RUNNING, action=BOOT)
3. sharding on → ProcessorShardBootstrap.startFreshProcess
4. sharding off → SupervisorActor.handleStartProcess
5. ControlActor / FlowActor / AbstractProcessor continuation
6. gRPC admission path (ReactorWorkerGrpcService → Reactor)
```

---

## Abort / resume / retry anomaly

```text
Symptom:
Control message ignored or wrong entity updated.

Check in order:
1. ReactorActions (resumeProcess / retryProcess / killProcess / initResponse)
2. DataHelper.checkServerDependency / sendAsyncMessage (non-sharded drop risk — known-issues K2)
3. SupervisorActor / SupervisorActorHelper routing
4. Sharded: bundle-then-message ShardEnvelope order
5. AbstractProcessor handleAbort / handleResume / handleRestart
6. ZRTaskActor.recoverForAbort (known-issues K6)
```

---

## Mailbox pressure / starvation

```text
Symptom:
Control or recover messages delayed; pressure recover fires.

Check in order:
1. SupervisorPriorityMailbox priorities
2. RecoverAfterMailboxPressure debounce on SupervisorActor
3. recovery batch size / fanout (reactor.recovery.*)
4. competing ZRProcess / BundleMessage volume
```

---

## Task executes twice / duplicate side effects

```text
Check in order:
1. AbstractTaskActor.recoverActor = initActor (at-least-once by design after restart)
2. Recovery double-BOOT: MemberRemoved / mailbox-pressure reload vs live entity (known-issues K5)
3. ControlActor.createActor InvalidActorNameException path (name reuse)
4. AbstractLinearActor.resolveRecoveryStartIndex (SequentialData commit skip)
5. ZQListenerCallBack / initResponse replays (RESPONSE duplicates)
```

---

## Process stuck RUNNING / PAUSE / RESPONSE_WAITING

```text
Check in order:
1. ProcessData row status/action in HBase (ReactorQuery) vs actor journal state
2. ResumeData row exists for the resumeId? (ReactorActions.schedule / ZRException.scheduleGlobal)
3. ResponseData/AsyncData rows for asyncId (resolveCallbackRouting)
4. DataHelper.check*Dependency returned null/false (silent drop — K2, K33)
5. Supervisor mailbox drops (P5 status messages, K8) / pressure logs
6. FlowActor.handlePause/handleResponseWaiting held due to pending resume/abort (static DataHelper sets)
7. Parallel/Batch aggregation edge cases (K16, K17)
8. Migration gate still waiting for MIGRATION_COMPLETE (K10)
```

---

## Wrong shard / entity not found / routing

```text
Check in order:
1. RecoveryRoutingUtil.resolveShardEntityId (root vs "-1") and shardIndex hash
2. ProcessorMessageExtractor / SequentialMessageExtractor (blank id => dropped with warning)
3. ShardEnvelope vs raw ZRMessage (extractor entity id for ZRMessage = root or process id)
4. shard count changed between deploys (re-maps entities; ProcessData.shardId stamped)
5. Bundle-then-message ordering (two envelopes, same entity)
```

---

## Throttling / outbound rate limit

```text
Check in order:
1. akka.actor.outbound-rate-limiter.* (enabled, integrations, key resolution order)
2. Limiter hosting: singleton (sharded, cluster-wide) vs local (per-node)
3. SequentialTask.outboundIntegrationKeys resolution in ControlActor
4. AbstractSequentialActor permit wait / PermitDenied retry / throttle retry cap
5. isOutboundRateLimited false positives ("429" substring, K29)
```

---

## Diagnostic commands (repo-real)

There is no JUnit/Akka TestKit reactor suite in this checkout.

| Need | Command / action |
|------|------------------|
| Full local product build | `bash build/local_build/run.sh` (runs `ant -Dpdt_name=qntrlworker`) |
| Skill static verify | `bash <skill folder>/scripts/verify.sh` |
| Dual-mode static review | `bash …/scripts/test-sharded.sh` and `test-nonsharded.sh` |
| In-process smoke (live worker) | `ExecutionLoadMetricsSmokeTest.run()` — metastore metrics only, not actor lifecycle |
| HTTP `/testing` suite | ScriptWorker/Qntrl/IoT/load only — **no reactor coverage** |

Grep examples (scoped):

```bash
rg -n "executeRecoveryOnce|ensureRecoveryCoordinator" source/reactor/com/qntrl/worker/reactor/actors
rg -n "sharding.enabled|isShardingEnabled" source/reactor product_package/conf/ReactorWorker
rg -n "persistAndDelete|SequentialRouter" source/reactor/com/qntrl/worker/reactor/actors/baseactor
```
