# Circuit Architecture Reference

## Module Map

```
source/
  worker/     com.qntrl.circuit          Main service (Spring-free, Struts2 actions)
  executor/   com.qntrl.execution        Execution engine (Akka actors + Reactor gRPC)
  store/      com.qntrl.store            HBase/event log persistence
  entity/     com.qntrl.entitymodel      Shared JPA/ActiveJDBC entities
  sdk/        com.zoho.circuit           Public Circuit SDK
  compression/                           Compression utilities
  qntrl/      com.qntrl                  Struts interceptors, logclient, QntrlThreadLocal
test/         com.qntrl.circuit          JUnit 5 tests
build/                                   Ant build (build.xml, ant.properties)
```

## Controller → Handler → DB Call Chain

Every REST endpoint is a Struts2 Action class. The pattern is rigid — follow it exactly.

```
XxxController extends QntrlRequestController implements ModelDriven<XxxBean>, RequestController
  index()    → list all
  create()   → create one
  show()     → get one (uses getEntityId() for path param)
  update()   → update one
  destroy()  → delete one
```

**Required imports every controller:**
```java
import com.qntrl.circuit.bean.request.QntrlRequestController;
import com.qntrl.circuit.exception.QntrlException;
import com.qntrl.circuit.response.ErrorResponse;
import org.apache.http.HttpStatus;
```

**Required error handling shape:**
```java
@Override
public void index() {
    try {
        // ... handler calls
        writeResponse(HttpStatus.SC_OK, responseObject);

    } catch (QntrlException ex) {
        LOGGER.log(Level.SEVERE, "Error message", ex);
        writeResponse(ErrorResponse.getInstance(ex));

    } catch (Exception ex) {
        LOGGER.log(Level.SEVERE, "Server Error message", ex);
        writeResponse(ErrorResponse.getServerError());
    }
}
```

## Handler Pattern

Handlers are singletons using double-checked locking:

```java
public class XxxHandler implements EntityHandler<XxxEntity, XxxBean> {
    private static volatile XxxHandler instance;

    private XxxHandler() {}

    public static XxxHandler getInstance() {
        if (instance == null) {
            synchronized (XxxHandler.class) {
                if (instance == null) {
                    instance = new XxxHandler();
                }
            }
        }
        return instance;
    }

    @Override
    public XxxEntity create(XxxBean bean) throws Exception {
        Long zsoid = QntrlThreadLocal.getZSOID();
        // ... transaction, validation, create
    }

    @Override
    public XxxEntity get(String id, XxxBean bean) throws Exception { ... }

    @Override
    public XxxEntity update(String id, XxxBean bean) throws Exception { ... }

    @Override
    public XxxEntity delete(String id, XxxBean bean) throws Exception { ... }
}
```

## Thread-local Context (always available in request scope)

`QntrlThreadLocal` is populated by the Struts2 interceptor before any controller executes.

```java
Long zsoid          = QntrlThreadLocal.getZSOID();         // org/scope id
Long zuid           = QntrlThreadLocal.getZUID();          // user id
Workspace workspace = QntrlThreadLocal.getWorkspace();
Service service     = QntrlThreadLocal.getService();
Integration integ   = QntrlThreadLocal.getIntegration();   // null for native Qntrl
ServiceOrg serviceOrg = QntrlThreadLocal.getServiceOrg();
```

`BPThreadLocal` (Blueprint thread local) is also populated:
```java
Long orgId     = BPThreadLocal.getOrgId();
Long workspaceId = BPThreadLocal.getWorkspaceId();
User user      = BPThreadLocal.getCurrentUser();
```

## Key Directories — Worker Module

| Directory | Purpose |
|---|---|
| `controller/` | 40+ REST controllers (CircuitsController, StatesController, ExecutionsController, ActionsController, etc.) |
| `handler/` | Business logic (CircuitHandler, ActionHandler, StateHandler, CredentialHandler, etc.) |
| `service/CircuitService.java` | Service orchestration |
| `db/` | Data access layer (WorkerDataAccess, ExecutionDataAccess, CircuitDataSet variants) |
| `bean/request/` | Request models (CircuitBean, ActionBean, ExecutionBean, StateBean, etc.) |
| `bean/transaction/` | Transaction beans (WorkerProcessBean, NoTransactionProcessBean) |
| `integration/` | External service handlers (crm/, catalyst/, dre/, flow/, mail/, sdp/, dc/, cloud/, logs360cloud/, reactor/) |
| `config/` | Configuration classes (CircuitConfiguration, ActionConfiguration, IntegrationConfiguration, TaskConfiguration) |
| `constant/` | Worker-specific enums (ResourceType, ResourceStatus, Status, EventStatus, etc.) |
| `exception/` | Exception hierarchy (QntrlException, ValidationException, EntityException, etc.) |
| `response/` | Response DTOs (CircuitResponse, CircuitResponseList, StateResponse, etc.) |
| `graph/` | Circuit graph (CircuitGraph, CircuitTraversal, CircuitConfigurationValidator) |
| `state/` | State model (State, StateMetadata) |
| `transaction/` | Transaction framework (TransactionHandler, TransactionManager, TransactionCommand) |
| `schema/` | JSON schema validation |
| `util/` | Utility classes |

## Key Directories — Executor Module

| Directory | Purpose |
|---|---|
| `actor/control/` | BranchActor, ParallelActor, BatchActor, SequentialActor, WaitActor, LinearActor, EndActor, SuccessActor, FailureActor |
| `actor/functional/` | ActionActor, WebhookActor, BridgeActor, FunctionActor, TaskActor, PowerActionActor, PassActor, SkipActor, CustomWebhookActor, CRMWebhookActor, etc. |
| `actor/notification/` | EmailActor |
| `task/control/` | Mirrors actor/control — BranchTask, ParallelTask, BatchTask, etc. |
| `task/functional/` | Mirrors actor/functional — ActionTask, BridgeTask, etc. |
| `task/notification/` | EmailTask |
| `constant/` | TaskType, TaskOperation, TaskOperationRegistry, TaskRegistry, ActorEvent, Status, IOType, BridgeTaskType, all XxxTaskOperation enums |
| `graph/` | ReactorWrapper, ReactorHelper, ProcessContext, ReactorProcessProperties |
| `handler/` | ExecutorHandler, ActorHandleable, CircuitCallBack, StateCallBack, EventLoggable |
| `exception/` | APIException, ActorException, ActorErrorType, ErrorConfig, StateErrorHandler, etc. |
| `process/` | Process class |
| `entity/` | ActorEntity, ProcessEntity, ExecutionCallback |
| `cache/` | CircuitExecutionCache, StatesMetaCache |

## Configuration

Main config file: `{app.home}/conf/circuit.conf` (Typesafe Config format)

```java
// Load in code:
CircuitConfiguration.getConfig()                    // full Config object
CircuitConfiguration.getFunctionConfig(Language.X)  // function-specific config
```

Service-specific config is per-entry in `circuit.conf` under the service name.

```java
// Access from Service enum:
service.getConfig()              // Typesafe Config
service.getDefaultBaseUrl()      // environment.base_url
service.getScopes()              // scopes list
service.getClientId()            // client_id
```

## Logging Pattern

```java
private static final Logger LOGGER = Logger.getLogger(ClassName.class.getName());

LOGGER.log(Level.INFO,  "Message with arg {0}", singleArg);
LOGGER.log(Level.INFO,  "Message with args {0} {1}", new Object[]{arg1, arg2});
LOGGER.log(Level.SEVERE, "Error message", exception);
LOGGER.log(Level.FINE,   "Debug message {0}", debugValue);
```

## Response Pattern

```java
// Success
writeResponse(HttpStatus.SC_OK, responseObject);

// QntrlException (business error)
writeResponse(ErrorResponse.getInstance(qntrlException));

// Server error
writeResponse(ErrorResponse.getServerError());

// Custom HTTP status
writeResponse(HttpStatus.SC_INTERNAL_SERVER_ERROR, ErrorResponse.getServerError());
```

## Adding a New Controller + Handler (checklist)

1. Create `XxxBean` in `bean/request/` extending appropriate base bean
2. Create `XxxHandler` in `handler/` — singleton, implements `EntityHandler<Entity, Bean>` if CRUD
3. Create `XxxController` in `controller/` — extends `QntrlRequestController`, implements `ModelDriven<XxxBean>` and `RequestController`
4. Create `XxxResponse` / `XxxResponseList` in `response/`
5. Register the controller as a Struts2 action in the Struts XML config (check existing struts-*.xml files for the pattern)
