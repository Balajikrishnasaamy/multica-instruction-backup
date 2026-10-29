# Actor & Task Patterns Reference

## Full 6-Step Pattern for Adding a New Task Type

When adding a new task type (e.g. "NOTIFY"), follow these steps in order:

### Step 1 — Add to TaskType enum

File: `source/executor/com/qntrl/execution/constant/TaskType.java`

```java
// Add alongside similar types. TaskType maps type name → Task class.
NOTIFY(NotifyTask.class),
```

The `getName()` method returns `StringUtils.lowerCase(name())` — so `NOTIFY` becomes `"notify"` in JSON.

### Step 2 — Create the Task class

The task class holds configuration deserialized from the circuit definition JSON.

**For a functional task** (in `source/executor/com/qntrl/execution/task/functional/`):
```java
package com.qntrl.execution.task.functional;

import com.qntrl.execution.constant.TaskType;

public class NotifyTask extends CustomResourceTask {

    private String channel;
    private String message;

    public NotifyTask(String name) {
        super(name, TaskType.NOTIFY);
    }

    public String getChannel() { return channel; }
    public void setChannel(String channel) { this.channel = channel; }

    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }
}
```

**For a control task** (in `source/executor/com/qntrl/execution/task/control/`):
```java
package com.qntrl.execution.task.control;

import com.qntrl.execution.constant.TaskType;
import com.qntrl.execution.exception.StateErrorHandler;
import com.qntrl.execution.task.QCTask;
import com.qntrl.store.entity.EventLogInfo;

import java.util.Map;
import java.util.Set;

public class NotifyTask extends com.qntrl.worker.reactor.tasks.flow.ZRTask<StateErrorHandler> implements QCTask {

    private Set<String> variables;
    private Long stateId;
    private String inputPath;
    private Map<String, String> resultSelector;
    private String resultPath;
    private String outputPath;
    private Boolean eventLog = true;
    private Boolean bindTask = false;

    public NotifyTask(String name) {
        super(name, TaskType.NOTIFY.getName());
    }

    @Override public TaskType getTaskType() { return TaskType.NOTIFY; }
    @Override public void setStateId(Long stateId) { this.stateId = stateId; }
    @Override public Long getStateId() { return stateId; }
    @Override public Set<String> getVariables() { return variables; }
    @Override public void setVariables(Set<String> variables) { this.variables = variables; }
    @Override public String getInputPath() { return inputPath; }
    @Override public void setInputPath(String inputPath) { this.inputPath = inputPath; }
    @Override public Map<String, String> getResultSelector() { return resultSelector; }
    @Override public void setResultSelector(Map<String, String> s) { this.resultSelector = s; }
    @Override public String getResultPath() { return resultPath; }
    @Override public void setResultPath(String p) { this.resultPath = p; }
    @Override public String getOutputPath() { return outputPath; }
    @Override public void setOutputPath(String p) { this.outputPath = p; }
    @Override public Boolean isEventLog() { return eventLog; }
    @Override public void setEventLog(Boolean e) { this.eventLog = e; }
    @Override public Boolean isBindTask() { return bindTask; }
    @Override public void setBindTask(Boolean b) { this.bindTask = b; }

    @Override
    public EventLogInfo createEventLogInfo() {
        EventLogInfo info = new EventLogInfo();
        info.setName(getName());
        return info;
    }
}
```

### Step 3 — Create the Actor class

The actor processes the task at runtime. There are two base classes:

**For functional actors** (extend `APIActor<T>` — in `source/executor/com/qntrl/execution/actor/functional/`):

`APIActor` already wires up `getTask()`, `getProcess()`, `getVariableMap()`, `getInputContext()`, `getProcessContext()`, payload management, async support, and event log prep. Override only what you need.

```java
package com.qntrl.execution.actor.functional;

import com.qntrl.execution.actor.APIActor;
import com.qntrl.execution.task.functional.NotifyTask;
import com.qntrl.worker.reactor.actors.baseactor.ZRTaskActor;
import com.qntrl.worker.reactor.config.ActorStatus;

import java.util.logging.Level;
import java.util.logging.Logger;

public class NotifyActor extends APIActor<NotifyTask> {

    private static final Logger LOGGER = Logger.getLogger(NotifyActor.class.getName());

    @Override
    public void execute() throws Exception {
        NotifyTask task = getTask();
        try {
            // business logic here
            // set result on IOEntity:
            getLocal().getIOEntity().setResult(result.toString());
            persistAndProcessStatus(ActorStatus.SUCCESS);

        } catch (Exception ex) {
            processUserException(ex);
        }
    }

    @Override
    protected void initActor() {
        try {
            execute();
        } catch (Exception ex) {
            processUserException(ex);
        }
    }

    @Override
    public Class<? extends ZRTaskActor> getActorClass() {
        return getClass();
    }
}
```

**For control actors** (extend `SystemActor` — in `source/executor/com/qntrl/execution/actor/control/`):

`SystemActor` requires you to handle `createReceive()`, `onActorEnter()`, `execute()`, `initActor()`, and `recoverActor()`:

```java
package com.qntrl.execution.actor.control;

import akka.actor.AbstractActor;
import com.qntrl.circuit.util.QntrlVariableUtil;
import com.qntrl.execution.handler.ActorHandleable;
import com.qntrl.execution.handler.ExecutorHandler;
import com.qntrl.execution.handler.GetTask;
import com.qntrl.execution.process.Process;
import com.qntrl.execution.task.control.NotifyTask;
import com.qntrl.store.entity.EventLogInfo;
import com.qntrl.worker.reactor.actors.actordata.ActorData;
import com.qntrl.worker.reactor.actors.baseactor.SystemActor;
import com.qntrl.worker.reactor.actors.baseactor.ZRTaskActor;
import com.qntrl.worker.reactor.config.ActorStatus;
import com.qntrl.worker.reactor.entity.ActorBundle;
import com.qntrl.worker.reactor.entity.ZRMessage;
import com.qntrl.worker.reactor.util.ReactorConstants;
import org.apache.commons.lang3.Strings;

import java.util.Map;
import java.util.logging.Logger;

public class NotifyActor extends SystemActor implements ActorHandleable, GetTask<NotifyTask> {

    private static final Logger LOGGER = Logger.getLogger(NotifyActor.class.getName());
    private ExecutorHandler handler;
    private Map<String, String> variableMap;

    @Override
    public AbstractActor.Receive createReceive() {
        return receiveBuilder()
            .match(ActorBundle.class, this::recoverActorState)
            .match(ZRMessage.class, m -> Strings.CS.equals(m.getType(), ReactorConstants.BOOT), this::handleBoot)
            .match(ZRMessage.class, m -> Strings.CS.equals(m.getType(), ReactorConstants.ABORT_RECOVER), this::recoverForAbort)
            .build();
    }

    @Override
    public void onActorEnter() throws Exception {
        Process process = (Process) getGlobal().getProcess();
        this.handler = new ExecutorHandler(process, getStateEntity());
        this.variableMap = QntrlVariableUtil.getVariables(process.getScopeId(), getFSMTask().getVariables());
        initLogClientThreadLocal();
    }

    @Override
    public void execute() {
        // business logic — call persistAndProcessStatus(ActorStatus.SUCCESS) or FAILURE
    }

    @Override
    protected ActorData initializeActorData() { return new ActorData(); }

    @Override
    protected void initActor() { execute(); }

    @Override
    protected void recoverActor() { execute(); }

    @Override
    public ExecutorHandler getHandler() { return handler; }

    @Override
    public Map<String, String> getVariableMap() { return variableMap; }

    @Override
    public Class<? extends ZRTaskActor> getActorClass() { return getClass(); }

    @Override
    public EventLogInfo getEventLogInfo() { return getTask().createEventLogInfo(); }
}
```

### Step 4 — Register Actor in the reactor's actor map

Find the actor registration file (typically in the reactor dependency, or in a config file that maps `TaskType.getName()` → Actor class). Search for where `BranchActor.class` is registered and add your actor in the same place.

```bash
# Find the registration:
grep -r "BranchActor" source/ --include="*.java" -l
grep -r "actorMap\|registerActor\|ActorRegistry" source/ --include="*.java" -l
```

### Step 5 — Add TaskOperation (only for TASK-type sub-operations)

If your new type is a sub-operation on the existing `TASK` node type (not its own top-level TaskType), create a `TaskOperation` enum instead:

File: `source/executor/com/qntrl/execution/constant/NotifyTaskOperation.java`

```java
package com.qntrl.execution.constant;

import com.google.gson.JsonElement;
import com.qntrl.circuit.bean.request.TaskBean;
import com.qntrl.circuit.constant.TaskModule;
import com.qntrl.circuit.context.IOContext;
import com.qntrl.circuit.response.LookupResponse;
import com.qntrl.circuit.util.CollectionProcess;
import com.qntrl.execution.task.functional.TaskTask;

@TaskOperationRegistry   // ← required for auto-discovery by TaskRegistry
public enum NotifyTaskOperation implements TaskOperation {

    SEND_EMAIL("send_email"),
    SEND_SMS("send_sms");

    private final String taskId;

    NotifyTaskOperation(String taskId) {
        this.taskId = taskId;
    }

    @Override
    public TaskModule getModule() {
        return TaskModule.NOTIFY;  // add this value to TaskModule enum too
    }

    @Override
    public String getTaskId() {
        return taskId;
    }

    @Override
    public CollectionProcess<LookupResponse> lookup(TaskTask task, String field, TaskBean taskBean) throws Exception {
        // return lookup options for a field
        return new CollectionProcess<>(LookupResponse.class);
    }

    @Override
    public JsonElement execute(TaskTask task, IOContext context, IOContext processContext) throws Exception {
        // bind payload and execute
        NotifyPayload payload = bind(context, NotifyPayload.class);
        // ... implementation
        return result;
    }
}
```

**The `@TaskOperationRegistry` annotation** causes `TaskRegistry` to auto-discover and register this enum at startup via classpath scanning. No manual registration needed.

### Step 6 — Add handler/controller if needed

Only if the new task type needs its own REST endpoints (rare). Follow architecture.md controller pattern.

---

## ActorStatus Values

```java
ActorStatus.SUCCESS        // task completed successfully
ActorStatus.FAILURE        // task failed (triggers error handler)
ActorStatus.CHANGE_FLOW    // branch changed flow (set changeTask on ActorData first)
ActorStatus.RESPONSE_WAITING // async — waiting for callback
ActorStatus.RUNNING        // still executing
```

## IOContext Usage in Actors

```java
// Get the input to this state
IOContext inputContext = getInputContext();       // APIActor
String input = (String) getLocal().getIOEntity().getInput();  // SystemActor

// Get process context (portal, requestor, workspace, circuit, execution)
IOContext processContext = getProcessContext();   // APIActor
IOContext processContext = handler.getProcessContext(getTask());  // SystemActor

// Read a JSONPath value
String value = inputContext.get("$.some.field", String.class);

// Evaluate a condition
boolean match = inputContext.evaluateCondition("$.count > 5");

// Set result (what flows to the next state)
getLocal().getIOEntity().setResult(jsonString);
```

## Variable Substitution

Circuit config JSON supports `${variableName}` placeholders. Resolve before using values:

```java
// In SystemActor.onActorEnter():
this.variableMap = QntrlVariableUtil.getVariables(process.getScopeId(), getFSMTask().getVariables());

// In APIActor, variableMap is pre-populated — just use it
Map<String, String> variableMap = getVariableMap();

// Apply substitution:
QntrlSubstitutor substitutor = new QntrlSubstitutor(
    new PlaceholderProcessor.Builder()
        .addResolver(new MapResolver(variableMap))
        .addResolver(new FakerResolver())
        .build()
);
String resolved = substitutor.replace(expression);
```

## Async Actor Pattern

For actors that send a request and wait for a webhook/callback response:

```java
// Before sending async request:
String[] ids = getAsyncEvent();
String processId = ids[0], asyncId = ids[1], event = ids[2];
beforeExecute(event, processId, asyncId, payload);

// Send async request with event as correlation ID

// After confirming request accepted:
afterExecute(substituteMap, asyncId);  // stores asyncId, sets RESPONSE_WAITING

// When callback arrives (receiveActorResponse):
public void receiveActorResponse(String asyncId, JsonObject response) throws Exception {
    // retrieve stored payload
    ResponseData responseData = ReactorWorker.getReactorQuery().getResponseData(asyncId);
    this.payload = JsonParser.parseString(responseData.getPayload()).getAsJsonObject();
    // process response, set result, call persistAndProcessStatus(ActorStatus.SUCCESS)
}
```

## Event Logging

All actors log events via `prepareAndPushLog(ActorEvent, substituteMap)` (in APIActor) or via `ExecutorHandler.pushEventLog()` (in SystemActor).

`ActorEvent` enum contains events like: `ACTION_TRIGGERED`, `ACTION_EXECUTED`, `ACTION_FAILED`, `BRIDGE_TRIGGERED`, `BRIDGE_EXECUTED`, `BRIDGE_FAILED`, `STATE_MACHINE_TRIGGERED`, `STATE_MACHINE_COMPLETED`, etc.

```java
// In APIActor:
Map<String, String> sub = new HashMap<>();
sub.put("actionId", actionId);
prepareAndPushLog(ActorEvent.ACTION_TRIGGERED, sub);

// With response data:
prepareAndPushLog(ActorEvent.ACTION_EXECUTED, sub, responseJson);
```

## Existing TaskOperation Enums (for reference)

| Enum | Module | File |
|---|---|---|
| `AzureUserTaskOperation` | AZURE_USER | constant/AzureUserTaskOperation.java |
| `AzureVmTaskOperation` | AZURE_VM | constant/AzureVmTaskOperation.java |
| `DatasetTaskOperation` | DATASET | constant/DatasetTaskOperation.java |
| `DateTimeTaskOperation` | DATE_TIME | constant/DateTimeTaskOperation.java |
| `GoogleCloudTaskOperation` | GOOGLE_CLOUD | constant/GoogleCloudTaskOperation.java |
| `JsonConversionTaskOperation` | JSON_CONVERSION | constant/JsonConversionTaskOperation.java |
| `MicrosoftTeamsTaskOperation` | MICROSOFT_TEAMS | constant/MicrosoftTeamsTaskOperation.java |
| `OktaUserTaskOperation` | OKTA_USER | constant/OktaUserTaskOperation.java |
| `PlatformAITaskOperation` | PLATFORM_AI | constant/PlatformAITaskOperation.java |

Look at any of these as a concrete model when creating a new `TaskOperation` enum.
