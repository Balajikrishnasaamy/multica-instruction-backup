# Integration Guide Reference

## Service Enum — All Integrated Services

File: `source/worker/com/qntrl/circuit/integration/Service.java`

| Enum constant | value | Notes |
|---|---|---|
| `CORE` | -1 | Bridge native modules only |
| `Qntrl` / `Orchestly` | 0 | Native — no integration entity needed |
| `ZohoCircuit` | 501 | Internal Zoho queue |
| `CLOUD` | 1 | ZohoCloud |
| `DRE` | 2 | Distributed Rule Engine |
| `ZohoCRM` | 3 | |
| `ZohoCatalyst` | 4 | |
| `SDPOnDemand` | 5 | |
| `ZohoWriter` | 6 | |
| `ZohoMail` | 8 | |
| `DesktopCentralCloud` | 9 | |
| `ZohoCliq` | 21 | OAuthServiceName is alias `ZohoChat` |
| `PlatformAI` | 127 | |
| `AzureVM` | 101 | External — Azure App OAuth |
| `Okta` | 102 | |
| `Google` | 103 | |
| `AzureUser` | 104 | External — Azure App OAuth |

**Common Service methods:**
```java
Service.getValueOf(String serviceName)  // by name
Service.valueOf(Number value)           // by byte value
Service.optValueOf(String name)         // Optional
service.isQntrl()                       // true only for Qntrl/Orchestly
service.isBridgeIntegration()           // true if integ_type = BRIDGE in config
service.isAzureAppOAuthIntegration()    // true for AzureVM, AzureUser
service.getConfig()                     // Typesafe Config from circuit.conf
service.getServiceName()                // string name for HTTP/API calls
service.getDefaultBaseUrl()             // environment.base_url from config
```

## Action Model

File: `source/worker/com/qntrl/circuit/integration/Action.java`

An `Action` represents one API call configuration loaded from the integration config file.

Key fields:
- `id` — action identifier (e.g. `"send_message"`, `"create_record"`)
- `name` — display name
- `method` — `HttpMethod` (GET, POST, PUT, DELETE, PATCH)
- `url` — URL template (may contain `{variable}` placeholders)
- `headers` — Map of static headers
- `contentType` — `HttpRequestContentType` (JSON, FORM, MULTIPART)
- `authType` — `IntegrationAuthType` (OAUTH, API_KEY, ZOHO_CONNECTION, etc.)
- `resultSelector` / `resultPath` — how to extract result from response
- `errorSelector` / `errorPath` — how to extract error from response
- `responseValidation` — JSON with `error_code` and `error_message` JSONPath
- `payload` — JSON Schema defining the action's input fields (from SchemaDriven)
- `preExecution` / `postExecution` — `ExecutionConfig` with optional JSONata transforms
- `internalRequest` — if true, uses internal Zoho network routing
- `asyncExecution` — if true, actor should use async flow

**Loading an action:**
```java
// From ActionHandler / ActionActor:
Integration integration = NoTransactionProcessBean.getInstance(zsoid)
    .optIntegration(service, integrationId)
    .orElseThrow(...);

Action action = ActionConfiguration.getAction(integration, actionId);
```

**For ZOHO_CONNECTION auth type (OAuth via credential):**
```java
if (action.getAuthType() == IntegrationAuthType.ZOHO_CONNECTION) {
    credentialId = task.getCredentialId();
    String connectionId = NoTransactionProcessBean.getInstance(zsoid)
        .optOAuth2Connection(workspaceId, credentialId)
        .orElseThrow(EntityException.notFound(Credential.class, credentialId));
    action.setCredentialIdPair(Pair.of(credentialId, connectionId));
}
```

## InternalIntegratedServiceHandler

File: `source/worker/com/qntrl/circuit/integration/InternalIntegratedServiceHandler.java`

This is the HTTP execution engine for all integration actions.

```java
InternalIntegratedServiceHandler handler =
    new InternalIntegratedServiceHandler(zsoid, service, integration);

// Sync execution:
Triple<HttpUriRequest, Pair<JsonElement, JsonElement>, Boolean> result =
    handler.execute(action, payload, variableMap, inputContext, processContext);
// result.getLeft()  = HttpUriRequest (for logging)
// result.getMiddle().getLeft()  = wrapped response (with status code, raw response)
// result.getMiddle().getRight() = processed result (after resultSelector)
// result.getRight() = success flag (false = API call failed)

// Async execution:
Triple<HttpUriRequest, HttpResponse, JsonObject> asyncResult =
    handler.asyncExecute(action, payload, variableMap, inputContext, processContext, extraHeaders);

// Handle async success/error response:
Pair<JsonElement, JsonElement> successPair =
    handler.handleAsyncSuccessResponse(statusCode, responseBody, action, variableMap, processContext);
Pair<JsonElement, JsonElement> failurePair =
    handler.handleAsyncErrorResponse(statusCode, responseBody, action, variableMap, processContext);
```

## Adding a New Integration (full pattern)

### 1. Add to Service enum

```java
// In Service.java:
MyService(50, OrgType.MYSERVICE, OrgConstants.OrgType.MYSERVICE, "MyService"),
```

### 2. Add circuit.conf entry

In `{app.home}/conf/circuit.conf`, add a `MyService { ... }` block with at minimum:
```hocon
MyService {
  alias_name = ""
  client_id = ""
  account_type = ORG
  integration_type = SINGLE
  integration_auth_type = OAUTH
  multiple.org = false
  multiple.integration = false
  multiple.workspace = false
  qntrl_native_integration = false
  disable.default.integration.workspace = false
  disable.feature.function = false
  disable.feature.webhook = false
  authorization_callback = true
  environment {
    base_url = "https://api.myservice.com"
    proxy = false
    headers {}
    parameters {}
  }
  scopes = []
  restricted_modules = []
  error_code_paths = ["$.error_code"]
  error_message_paths = ["$.message"]
}
```

### 3. Create integration handler directory and files

```
source/worker/com/qntrl/circuit/integration/myservice/
  MyServiceHandler.java    # business logic (fetch resources, handle auth)
  MyServiceRestAPI.java    # REST API constants (URLs, headers)
```

Pattern for `MyServiceHandler.java`:
```java
package com.qntrl.circuit.integration.myservice;

public class MyServiceHandler {
    private static volatile MyServiceHandler instance;

    private MyServiceHandler() {}

    public static MyServiceHandler getInstance() {
        if (instance == null) {
            synchronized (MyServiceHandler.class) {
                if (instance == null) { instance = new MyServiceHandler(); }
            }
        }
        return instance;
    }

    public SomeResponse doSomething(Long zsoid, Integration integration, ...) throws Exception {
        // implementation
    }
}
```

### 4. Register action configs

If the integration has actions (invocable in circuit states):
- Create action config JSON files and register them in `ActionConfiguration`
- Each action JSON follows the `Action` model schema

### 5. Add actor/task if needed

If the integration can be triggered as a circuit state, create an `XxxActor`/`XxxTask` following actor-patterns.md.

---

## Bridge Integration Pattern

Bridge is the on-premise agent integration. Key classes:

- `BridgeActor` — handles sync and async bridge calls via gRPC
- `BridgeTaskType` — enum of all bridge sub-task types (SQL, REST, script, AD, Windows app, etc.)
- `BridgeWorkerAgent.sendMessage()` — gRPC sync call
- `BridgeWorkerAgent.sendAsyncMessage()` — gRPC async call

**BridgeTask fields:**
- `getResourceId()` — bridge server ID or cluster ID
- `getBridgeTaskType()` — the sub-task type (determines `task_name` in gRPC payload)
- `getIsClusterRequest()` — if true, route to cluster; else named server
- `getSync()` — sync vs async execution
- `getTimeout()` — timeout in seconds

**BridgeTaskType** provides:
```java
bridgeTaskType.getData(task, variableMap, inputContext, processContext)  // builds JsonObject payload
bridgeTaskType.getModule()         // module name string
bridgeTaskType.getModuleLinkName() // module link name for gRPC
bridgeTaskType.getService()        // service identifier string
```

---

## DRE Integration Pattern

File: `source/worker/com/qntrl/circuit/integration/dre/`

- `DelugeFunctionHandler` — executes Deluge functions via DRE
- `Connection` — DRE connection model
- `Connector` — connector config (loaded from Service.getDREConnector())

```java
Service.DRE.getDREConnector()  // returns Connector config
```

---

## IOContext in Integrations

All integration calls receive:
- `inputContext` — the current state's input JSON
- `processContext` — portal/requestor/workspace/circuit/execution/integration metadata

Access values:
```java
String value = processContext.get("$.portal.id", String.class);
String workspaceId = processContext.get("$.workspace.id", String.class);
String integrationId = processContext.get("$.integration.id", String.class);
```

---

## IntegrationConfiguration

File: `source/worker/com/qntrl/circuit/config/IntegrationConfiguration.java`

```java
// Get service-level Typesafe Config:
Config serviceConfig = IntegrationConfiguration.getServiceConfig("ZohoCRM");

// Used inside Service enum constructor to load per-service config from circuit.conf
```

---

## External Integrations (non-Zoho)

External integrations (AzureVM, AzureUser, Okta, Google) use Azure App-registration style OAuth.

- Authorization: `AzureController` / service-specific controller
- `Service.isAzureAppOAuthIntegration()` returns true for AzureVM, AzureUser
- They have their own `XxxTaskOperation` enums under `source/executor/com/qntrl/execution/constant/`

To add a new external integration:
1. Add to `Service` enum with value > 100
2. Create config in circuit.conf
3. Create `XxxTaskOperation` enum implementing `TaskOperation` with `@TaskOperationRegistry`
4. Create actor/task if needed
5. Create authorization controller if OAuth handshake is needed
