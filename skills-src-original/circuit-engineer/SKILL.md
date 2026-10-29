---
name: circuit-engineer
description: Expert knowledge of the Circuit codebase — Zoho/Qntrl's Java state-machine orchestration microservice ("Worker", main branch CIRCUIT_V3_STAGING). Use for any Circuit repo task — feature work, bug fixes, refactoring, code review, tests, architectural analysis. Covers module layout, Ant build, domain model, and the executor pipeline. Trigger when the task involves actors (Branch/Parallel/Batch/Wait/Linear/Series), controllers, handlers, services or the DB layer; integrations (CRM, Catalyst, Bridge, DRE, Cliq, Azure, Okta, Google Cloud); state machine / Circuit / Worker logic; the executor pipeline, TaskType, TaskRegistry or TaskOperation enums; build.xml or ant.properties; or tests under test/.
---

# Circuit (Worker) Engineering

Circuit — internally "Worker" — is a state-machine orchestration microservice in the Qntrl/Zoho
Blueprint platform. Users define directed-graph workflows ("Circuits") of states and transitions
that execute backend operations (API calls, functions, webhooks, scripts) across Zoho and
third-party services. The service owns circuit CRUD, execution and scheduling, credential
management, and integrations.

**Stack:** Java 11+, Apache Struts 2.6, Gson 2.9, HBase, HOCON config, JGraphT 1.3,
Apache Ant (build), Tomcat 9.

If the repo has an `AGENTS.md` at its root, read it first — it is authoritative on setup commands
and current structure, and supersedes this file where they disagree.

## Build

Apache Ant only (`build/build.xml`, `build/ant.properties`). Product `WORKER`, version `1.1.0.0`.

- Full build: `cd build && ant`
- Clean: `cd build && ant clean`
- **Never run `mvn`, `gradle`, or `npm install`** — this project uses Ant exclusively.

The full build pulls dependencies from internal Zoho infrastructure
(`build.zohocorp.com`, `build.csez.zohocorpin.com`). If those hosts are unreachable it needs
pre-downloaded dependencies in `build/WORKER/dependencies/`. For code-only changes, rely on the
IDE's compile output in `out/` rather than attempting a full build.

## Repo layout

```
source/
  worker/        # Main service → qntrl-circuit.jar (com.qntrl.circuit)
  executor/      # Task execution engine (com.qntrl.execution)
  store/         # Event/transition log persistence (com.qntrl.store)
  entity/        # AUTO-GENERATED entity model (com.qntrl.entitymodel.circuit) — do NOT edit
  sdk/           # Zoho Circuit SDK (com.zoho.circuit)
  compression/   # Data compression utilities
  qntrl/         # Struts interceptors, logclient, threadlocal
test/            # Tests (com.qntrl.circuit)
build/           # Ant build system
resources/       # Entity data-dictionary DTD and templates
product_package/ # Deployment packaging
```

**Worker** (`source/worker/com/qntrl/circuit/`): `controller/` (Struts REST controllers),
`handler/` (business logic, singletons), `service/`, `db/` (WorkerDataAccess, ExecutionDataAccess,
CircuitDataSet), `integration/`, `externalintegration/`, `bean/request/`, `bean/transaction/`,
`response/`, `exception/`, `graph/` (JGraphT circuit validation), `state/`, `config/` (HOCON),
`rest/`, `validation/`, `constant/`, `transaction/`, `util/` (ParserUtil, JsonPathUtil).

**Executor** (`source/executor/com/qntrl/execution/`):
- `actor/control/` — Branch, Parallel, Batch, Sequential, Series, Linear, TopLinear, Process,
  Wait, End, Success, Failure
- `actor/functional/` — Action, Webhook, Bridge, Function, PowerAction, Pass, Skip, Task,
  CustomWebhook, CRMWebhook
- `actor/notification/` — notification actors
- `task/` — task implementations mirroring the actor types
- `constant/` — TaskType, TaskOperation enums, TaskRegistry, TaskOperationRegistry, Status,
  ActorEvent
- `graph/` — ReactorWrapper, ReactorHelper, ProcessContext, ReactorProcessProperties

## Domain model

- **Circuit / Worker** — a state machine definition (blueprint) for a backend workflow
- **State** — an individual node in the state machine
- **Execution** — a running instance of a Circuit, moving through states
- **Actor** — the execution-time unit that processes a state/task type; every task type has a
  paired Actor class in the executor module
- **Task** — the configuration counterpart to an Actor; describes what to execute
- **TaskType** — enum registry of all task node types (BRANCH, PARALLEL, BATCH, ACTION, WEBHOOK,
  FUNCTION, BRIDGE, …)
- **TaskOperation** — sub-operations for complex task types (DateTimeTaskOperation,
  BridgeTaskOperation, AzureUserTaskOperation, …)
- **IOContext** — runtime context threaded through the execution graph (input/output,
  credentials, metadata)
- **ReactorWrapper** — wraps the Project Reactor-based execution graph
- **Bridge** — on-premise agent integration for running tasks inside customer networks
- **Power Action** — elevated automation actions within Qntrl
- **DRE** — Distributed Rule Engine integration
- **Credential** — secure credential store for integration auth (OAuth, API keys, PL/SQL)

## Adding a new task type

1. Add the enum value to `TaskType.java` and register it in `TaskRegistry.java`
2. Create `XxxTask.java` in the appropriate `task/` subdirectory
3. Create `XxxActor.java` in the corresponding `actor/` subdirectory
4. Register the actor in `TaskOperationRegistry.java`; if it has sub-operations, add an
   `XxxTaskOperation.java` enum
5. Add handler logic under `source/worker/com/qntrl/circuit/handler/` if a new handler is needed
6. Add a controller endpoint under `source/worker/com/qntrl/circuit/controller/` if it is exposed
   over REST

After adding an enum value, grep for every `switch` that enumerates that enum and confirm the new
value is handled.

## Adding a new integration

1. Create a directory under `source/worker/com/qntrl/circuit/integration/<service>/` — or under
   `externalintegration/` for third-party providers (that package holds `google`, `oauth2`, `okta`)
2. Extend `InternalIntegratedServiceHandler` (a class, not an interface — see `CatalystHandler`
   and `CrmHandler` for the pattern). Implement `IntegratedServiceFunction` /
   `IntegratedServiceAuthorizable` where those contracts apply
3. Register in `source/worker/com/qntrl/circuit/config/IntegrationConfiguration.java`
4. Add a matching actor/task if the integration is invocable as a task node

## How to work

1. **Understand** — read the relevant existing files before writing anything. Grep to locate
   related code. Never assume an implementation; verify it.
2. **Plan** — identify every file that must change. For new task types follow the six steps above.
   For bug fixes, trace the chain controller → handler → service → db, or into the executor.
3. **Implement** — follow the conventions already in the file you are editing.
4. **Verify** — grep for consistency across switches, registries, and call sites. Check import
   chains and referenced classes for compilation problems.
5. **Report** — summarize what changed and why, citing `file_path:line_number` for key changes.

## Code style

- Java, no Lombok — confirm against existing files before using any annotation library
- No comments unless the WHY is genuinely non-obvious
- Match the surrounding brace style, indentation, and import ordering
- Prefer editing existing files over creating new ones
- No error handling for impossible cases — trust the framework
- No feature flags, no backwards-compatibility shims
- Never edit `source/entity/` — it is generated

## Safety

- Never push to a remote, and never commit, without explicit user instruction
- No destructive schema changes or dropped tables without explicit instruction
- Run `git status` before any destructive git operation
- Do not modify `build/build.xml` unless asked — its dependency ordering is load-bearing
