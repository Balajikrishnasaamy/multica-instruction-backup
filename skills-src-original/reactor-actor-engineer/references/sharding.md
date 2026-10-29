# Sharding (reference)

Always evaluate **both** modes:

```text
reactor.sharding.enabled=true
reactor.sharding.enabled=false
```

Config source: `product_package/conf/ReactorWorker/server.conf`

```hocon
reactor {
  sharding {
    enabled: false          # default OFF in this repo
    processor { number-of-shards: 30 }
    sequential { number-of-shards: 10 }
  }
  migration {
    enabled: false          # cutover gate when enabling sharding
  }
}
```

Runtime reader: `config/ReactorServerConfiguration.java` (`isShardingEnabled()`).

Bootstrap: `main/ReactorWorker.java` → `initShardedActorSystem()` / `initNonShardedActorSystem()`.

---

## Mode differences (do not invent)

| Concern | Sharded (`true`) | Non-sharded (`false`) |
|---------|------------------|------------------------|
| Process start | `ProcessorShardBootstrap.startFreshProcess` → `ShardEnvelope` to `ProcessorShard` | Local supervisor `handleStartProcess` |
| Sequential bundle | `SequentialShard` via `ShardEnvelope` | Supervisor-local SequentialActor |
| Abort / resume / retry / partial restart | Bundle then message via `ShardEnvelope` | Local recreate + bundle patterns |
| Supervisor | ClusterSingleton proxy | Local `SupervisorActor` |
| Outbound rate limiter | ClusterSingleton (cluster-wide rates) | Local `/user/outboundRateLimiter` (per-node rates) |
| Boot recovery | Immediate unless `migration.enabled=true` | Immediate |
| MemberRemoved reload | Debounced recover (sharded only) | N/A |
| Mailbox-pressure reload | Yes | Yes |
| SBR | Kept on ActorSystem path | Stripped (`withoutSplitBrainResolver`) |

Shard region code: `sharding/*`, especially `ProcessorShardBootstrap.java`.

---

## Migration gate

When `reactor.migration.enabled=true` **and** sharding is on:

- Each node sync-migrates ProcessData/ResumeData node-key → `hbase.common.user.key`
- Supervisor boot recovery waits until **all** seed nodes publish `MIGRATION_COMPLETE:<node>`
- Then `executeRecoveryOnce("MIGRATION_SYNC")`

Comment in `server.conf`: one-time cutover when enabling sharding; never turn sharding off after this.

`MemberRemoved` / mailbox-pressure reloads are **not** blocked by `migration.enabled`.

---

## Validation reality (repo scan)

There is **no** automated sharded/non-sharded test suite in this checkout.

Use:

- [../scripts/test-sharded.sh](../scripts/test-sharded.sh)
- [../scripts/test-nonsharded.sh](../scripts/test-nonsharded.sh)

These run static dual-mode review checks against mapped sources and config. Runtime proof requires a deployed cluster with the matching `server.conf` values.
