# Persistence (reference)

Verify with Read/Grep on the listed files before changing journaled behavior.

Primary files:

- `actors/baseactor/ZRPersistence.java`
- `actors/baseactor/ZRVariables.java`
- `actors/abstractactor/AbstractProcessor.java`
- `product_package/conf/ReactorWorker/server.conf` (`reactor.persistence.*`)
- `product_package/conf/ReactorWorker/application.conf` (Akka persistence / Cassandra plugin)

---

## Invariants

```text
Journaled:
- ZRGlobals
- ActorData
- IOEntity

replyRef is never journaled.

persistAndDelete:
- persist
- Cassandra Cleanup
- not deleteMessages

Sequential actors:
- bypass journal persistence via SequentialRouter in ZRPersistence

Snapshots:
- Snapshot plugin may be configured
- Reactor actors do not call saveSnapshot
```

---

## Compatibility-sensitive surfaces

Treat as breaking unless TaskSpec + tests prove otherwise:

- journaled event types / fields
- `persistenceId` construction
- event class names (serializer / replay)
- writer UUID / event history assumptions
- `persistAndDelete` vs plain persist
- inheritance changes that alter which base class journals

---

## Replay / persistence failure checklist

Symptom: replay or persistence compatibility error.

Check in order:

1. `persistenceId`
2. event class
3. journaled fields (`ZRGlobals` / `ActorData` / `IOEntity`)
4. serializer config in `application.conf`
5. writer UUID / event history
6. snapshot configuration (even if unused by actors)
7. `persistAndDelete` / Cassandra `Cleanup` behavior
8. whether the actor is sequential (`SequentialRouter` skip path)

---

## Related recovery data (HBase, not Akka journal)

Recovery loads process/schedule state from HBase via `query/ReactorQuery.java` (`getRecoverableRootProcesses`, resume data). Do not conflate HBase process rows with Cassandra journal events when diagnosing “not recovered” vs “replay failed”.
