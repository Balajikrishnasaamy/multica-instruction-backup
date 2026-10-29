# Circuit Engineer — Knowledge Pack Index

This pack contains the domain references, scripts, and templates used by the `circuit-engineer` agent.
Load the reference for your task type BEFORE writing any code.

## References — when to load each

| Task | Load |
|---|---|
| New TaskType, Actor, Task class | `references/actor-patterns.md` |
| New integration or modifying existing | `references/integration-guide.md` |
| DB queries, DataSet, predicates, transactions | `references/db-patterns.md` |
| New controller, handler, REST endpoint | `references/architecture.md` |
| New controller + HTTP param validation + security | `references/architecture.md` + `references/struts-security.md` |
| Writing or fixing tests | `references/test-patterns.md` |
| Cross-cutting change, general orientation | `references/architecture.md` |

## Scripts — run before searching manually

Point them at the repo with `CIRCUIT_REPO_ROOT=<checkout>` when you run them from outside it (they also find `./circuit` and the repository you are in).


| Script | Purpose |
|---|---|
| `scripts/find-actor.sh <Name>` | Locate Actor, Task, Handler, Controller, TaskOperation for a given task type |
| `scripts/find-references.sh <Symbol>` | Find all Java files referencing a symbol |

## Templates — scaffold from, then fill in logic

| Template | Use for |
|---|---|
| `templates/NewFunctionalActor.java.tmpl` | New functional actor (extends APIActor) |
| `templates/NewFunctionalTask.java.tmpl` | New functional task (extends CustomResourceTask) |
| `templates/NewControlActor.java.tmpl` | New control-flow actor (extends SystemActor) |
| `templates/NewControlTask.java.tmpl` | New control-flow task (extends ZRTask) |
| `templates/NewController.java.tmpl` | New REST controller (extends QntrlRequestController) |
| `templates/NewHandler.java.tmpl` | New singleton handler |
| `templates/NewBean.java.tmpl` | New request bean (Struts2 ModelDriven model) |
| `templates/NewResponse.java.tmpl` | New response DTO (single entity + list variant) |
| `templates/NewTaskOperation.java.tmpl` | New @TaskOperationRegistry enum |

## Key pinned files (verify before every task)

| What | Path |
|---|---|
| Actor → XML registration | `product_package/conf/ReactorWorker/circuit_tasks.xml` |
| State type → Task class mapping | `source/worker/com/qntrl/circuit/constant/StateConfigType.java` |
| TaskType enum | `source/executor/com/qntrl/execution/constant/TaskType.java` |
| Security (web endpoints) | `product_package/conf/Security/QntrlCircuit/security-web.xml` |
| Security (API endpoints) | `product_package/conf/Security/QntrlCircuit/security-api.xml` |
