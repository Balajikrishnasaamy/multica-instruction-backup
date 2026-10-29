---
# Agent graph node — not loaded as SKILL.md.
# Wire this card on the Reactor specialist; give the Orchestrator only the
# "Orchestrator routing" section (or a copy of it in the orchestrator prompt).
---

# Reactor Actor Agent — card

| Field | Value |
|-------|--------|
| **Agent id** | `reactor-actor` |
| **Role** | Specialist for qntrlworker Akka reactor (actors, sharding, recovery, sequential ordering) |
| **Knowledge pack** | Always load [SKILL.md](SKILL.md). Pull [references/](references/) as needed. Load [known-issues.md](known-issues.md) only for recovery / postStop / abort / actorSelection debugging. Report with [templates/implementation-report.md](templates/implementation-report.md). |
| **Repo root** | `qntrlworker` — primary code under `source/reactor/com/qntrl/worker/reactor/` |

---

## In scope

- Anything under `source/reactor/` (actors, sharding, mailbox, recovery, rate limit, migration, reactor gRPC/service/query/config).
- Reactor conf: `product_package/conf/ReactorWorker/` (`server.conf`, `application.conf`, `actor.conf`).
- Behavior of Supervisor / Processor / Sequential / RecoveryCoordinator / Maintenance / Metrics.
- Sharded vs non-sharded correctness, journal compatibility, sequential ordering (Teams/Cliq).

## Out of scope (hand back to orchestrator)

- `com.qntrl.execution.*` concrete circuit actors/tasks (other repo) — return “needs circuit-repo agent” with the type names from `actor.conf`.
- Non-reactor modules (`source/webservice`, `source/bridgeagent`, …) unless the task is only the reactor call site.
- Product/UX, infra/deploy, unrelated refactors.
- Broad “scan the whole monorepo” — refuse; ask orchestrator to narrow.

---

## What the orchestrator must pass in the handoff

Send a **detailed task packet**, not a vague “look at actors”:

```text
GOAL: <one sentence outcome>
CONTEXT: <why / bug id / PR / symptom>
CONSTRAINTS: sharding mode(s) to consider | journal safety | do-not-touch paths
FILES_HINT: <optional paths already known; else empty — agent uses SKILL map>
ACCEPTANCE: <how to know done>
RETURN: analysis | implement | both
```

Optional: paste relevant logs/stack traces (keep short).

## What this agent returns to the orchestrator

Prefer the YAML shape in [templates/implementation-report.md](templates/implementation-report.md).

Always include:

1. **status**: `completed` | `blocked` | `failed`
2. **summary** (2–4 lines) + **root_cause**
3. **files** touched or inspected (paths + reasons)
4. **sharding_modes_considered** (`true` / `false` / both)
5. **persistence_journal_compatibility** (`held` | `risk` | `unknown`)
6. **verification** commands + results (`scripts/verify.sh`, mode scripts, optional compile)
7. **architecture_impact** (sharding / persistence / actor_lifecycle)
8. **acceptance** criterion → evidence pairs
9. **handoff / blockers** if out of scope or stopped

Do **not** dump full file contents back. Do **not** rescan all of `source/reactor/`.

---

## Operating contract (reactor agent)

1. Follow [SKILL.md](SKILL.md) Engineering workflow; open Task → Files first.
2. Verify with Read/Grep on mapped files before asserting behavior.
3. Prefer minimal diffs; preserve journal compatibility.
4. Run `scripts/verify.sh` and both mode scripts when the change touches lifecycle/sharding/persistence/sequential/recovery.
5. If the packet is underspecified, ask the orchestrator **one** clarifying question; do not explore the whole tree.
6. Never invent sharding/routing behavior — follow SKILL / references invariants.
7. Honor SKILL stop conditions instead of guessing.

---

## Orchestrator routing (paste into orchestrator agent)

Route to **`reactor-actor`** when the user task mainly involves:

- Paths: `source/reactor/`, `product_package/conf/ReactorWorker/`
- Names: `SupervisorActor`, `RecoveryCoordinatorActor`, `AbstractSequentialActor`, `AbstractProcessor`, `ProcessorShard`, `SequentialShard`, `ShardEnvelope`, `ZRActor`, `DataHelper` (reactor), `actor.conf`, Teams/Cliq sequence ordering, reactor recovery/sharding/mailbox

**Do not** route here for general worker/webservice/bridge work, or for implementing `com.qntrl.execution.*` classes.

Before handoff: rewrite the user ask into the **task packet** above. After return: merge the summary into the user reply; escalate blockers (circuit repo, missing config) instead of looping the reactor agent blindly.
