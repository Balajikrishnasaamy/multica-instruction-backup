# DB Patterns Reference

## WorkerDataAccess — Persistence Factory

File: `source/worker/com/qntrl/circuit/db/WorkerDataAccess.java`

The base class for all data access. Never instantiate directly — use the static factory methods.

### Persistence Type Selection

| Factory method | When to use |
|---|---|
| `getPersistence()` | Writes within a transaction context |
| `getPersistence(scopeId)` | Writes scoped to a specific org |
| `getCachedPersistence()` | Reads for frequently accessed, cacheable data |
| `getCachedPersistence(scopeId)` | Cached reads scoped to org |
| `getReadOnlyCachedPersistence()` | Read-only cached access (no writes) |
| `getNoTransactionPersistence()` | Reads outside any transaction (most common for reads) |
| `getNoTransactionPersistence(scopeId)` | Org-scoped reads outside transaction |
| `getNoCachePersistence()` | Reads that must bypass cache |
| `getNoCachePersistence(scopeId)` | Org-scoped cache-bypassing reads |

**Golden rule:** Use `getNoTransactionPersistence()` for most reads in handlers. Use `getPersistence()` only inside a `TransactionManager` block.

### CRUD Operations

```java
WorkerDataAccess da = WorkerDataAccess.getNoTransactionPersistence(zsoid.toString());

// CREATE
EntityDataSet result = da.create(entity);
EntityDataSet result = da.create(Collection<Entity> entities);

// READ — always via BeanPredicate
EntityDataSet dataSet = da.get(predicate);
EntityDataSet dataSet = da.get(predicate, joins);
EntityDataSet dataSet = da.get(predicate, range);
EntityDataSet dataSet = da.get(predicate, sortColumn);

// READ with pagination
ResponseDataSet rds = da.getLimit(predicate, indexableBean);
ResponseDataSet rds = da.getLimit(predicate, indexableBean, joins);
ResponseDataSet rds = da.getSort(predicate, sortableBean);
ResponseDataSet rds = da.get(predicate, entityBean);  // handles search + pagination + sort

// COUNT
Long count = da.getCount(predicate);
Long count = da.getCount(predicate, joins);

// UPDATE
da.update(entity);                     // by primary key
da.update(entity, predicate);          // by custom predicate

// DELETE
da.delete(predicate);
```

### BeanPredicate Construction

Predicates are built using static methods on entity classes:

```java
// Single predicate:
BeanPredicate pred = Circuit.linkNameEqual(circuitId);

// Combined (AND):
BeanPredicate pred = BeanPredicate.getAllPredicate(
    Resource.workspaceIdEqual(workspaceId),
    Resource.typeEqualEnum(ResourceType.CIRCUIT),
    Resource.statusNotEqualEnum(ResourceStatus.DELETED)
);

// From a list:
BeanPredicate pred = BeanPredicate.getAllPredicate(predicateList);

// OR predicates:
BeanPredicate pred = BeanPredicate.getAnyPredicate(pred1, pred2);
```

### Joins

```java
// Common joins (each entity class provides static join factories):
Join wsJoin    = Resource.getWorkspaceIdJoin(Join.LEFT_JOIN);
Join circJoin  = Circuit.getCircuitIdJoin(Join.LEFT_JOIN);
Join execJoin  = Execution.getResourceIdJoin(Join.LEFT_JOIN);
Join intWsJoin = IntegrationWorkspace.getWorkspaceIdJoin(Join.LEFT_JOIN);

// Attach joins to query:
EntityDataSet ds = da.get(predicate, wsJoin, circJoin);
```

### Reading Entities from EntityDataSet

```java
EntityDataSet ds = da.get(predicate, joins);

// Get all of a type:
Iterator<Circuit> circuits = ds.getEntities(Circuit.TABLE_NAME);

// Get optional single entity:
Optional<Circuit> opt = ds.optEntity(Circuit.TABLE_NAME);

// Get single entity (throws if absent):
Circuit c = (Circuit) ds.optEntity(Circuit.TABLE_NAME)
    .orElseThrow(EntityException.notFound(ResourceType.CIRCUIT, circuitId));
```

### ResponseDataSet

Returned by `getLimit` / `getSort` / `get(predicate, entityBean)`. Wraps `EntityDataSet` + pagination metadata.

```java
ResponseDataSet rds = da.get(predicate, bean, joins);
EntityDataSet innerDs = rds.getDataSet();
long total = rds.getTotal();
int startIndex = rds.getStartIndex();
int range = rds.getRange();
```

---

## ExecutionDataAccess

File: `source/worker/com/qntrl/circuit/db/ExecutionDataAccess.java`

Extends `WorkerDataAccess`. Use for Execution entity queries.

```java
ExecutionDataAccess eda = ExecutionDataAccess.getNoTransactionPersistence();

List<Execution> executions = eda.getExecutions(executionBean);
List<Execution> executions = eda.getExecutions(service, executionBean);
```

---

## CircuitDataSet Variants

Abstract base class for configuration datasets that combine a circuit graph with DB entities.

| Class | File | Purpose |
|---|---|---|
| `CircuitDataSet` | db/CircuitDataSet.java | Abstract base |
| `CircuitBridgeDataSet` | db/CircuitBridgeDataSet.java | Bridge config per state |
| `CircuitCredentialDataSet` | db/CircuitCredentialDataSet.java | Credential associations |
| `CircuitResourceDataSet` | db/CircuitResourceDataSet.java | Resource associations |
| `CircuitScriptDataSet` | db/CircuitScriptDataSet.java | Script associations |
| `CircuitVariableDataSet` | db/CircuitVariableDataSet.java | Variable definitions |

These are used during circuit configuration load to enrich states with their DB-backed config.

```java
// Pattern for using a CircuitDataSet:
CircuitGraph<State, StateConfigType> stateGraph = ...;
CircuitBridgeDataSet ds = new CircuitBridgeDataSet(service, workspace, stateGraph, suppressException);
Optional<BridgeEntity> bridgeEntity = ds.optEntity(state);
Set<BridgeEntity> bridgeEntities = ds.getEntities(state);
```

---

## Transaction Pattern

All writes that span multiple entities must use the transaction framework.

File locations: `source/worker/com/qntrl/circuit/transaction/`

```java
TransactionContext context = new TransactionContext();
context.set(ContextType.Application.ZSOID, Long.class, zsoid);
context.set(ContextType.Application.ZUID, Long.class, zuid);
context.set(ContextType.Application.WORKSPACE, Workspace.class, workspace);

TransactionManager transaction = new TransactionManager(context);
Deque<TransactionCommand> commands = new TransactionHandler(context, service)
    .createCircuit(zsoid, zuid, circuitBean, stateGraph);

transaction.execute(commands);

// After execute, retrieve results from context:
Circuit circuit = context.get(ContextType.Circuit.CIRCUIT);
```

**Key ContextType values:**
- `ContextType.Application.ZSOID`
- `ContextType.Application.ZUID`
- `ContextType.Application.WORKSPACE`
- `ContextType.Circuit.CIRCUIT`
- `ContextType.Execution.EXECUTION`

---

## WorkerProcessBean / NoTransactionProcessBean

Higher-level wrappers over WorkerDataAccess that combine multiple DA calls.

```java
// With transaction (for writes):
WorkerProcessBean.getInstance().getCircuit(circuitId, bean);
WorkerProcessBean.getInstance().deleteCircuit(circuitId, bean);

// Without transaction (for reads):
NoTransactionProcessBean.getInstance(zsoid).getCircuit(circuitId);
NoTransactionProcessBean.getInstance(zsoid).optIntegration(service, integrationId);
NoTransactionProcessBean.getInstance(zsoid).getStateEntities(circuitId, versionId, stateEntityType);
NoTransactionProcessBean.getInstance(zsoid).addAuditLog(auditLog);
```

---

## Entity Adapter Pattern

`EntityAdapter` converts between entity objects and DB rows.

```java
// Rarely used directly — WorkerDataAccess handles this internally.
// But when you need raw DataObject:
EntityAdapter<Circuit> adapter = EntityAdapter.getInstance(circuit);
DataObject dob = new WritableDataObject();
dob.addRow(adapter.getWritableRow());
```

---

## PredicateAdapter

Converts `BeanPredicate` to `SelectQuery` / `Criteria`.

```java
// Also used internally by WorkerDataAccess.
// Exposed for custom SelectQuery needs:
PredicateAdapter pa = new PredicateAdapter(predicate);
SelectQuery sq = pa.getSelectQuery(joins, sortColumn);
sq.setRange(range);
```

---

## Range / Pagination

```java
// From EntityBean (QntrlRequestController populates from query params):
Range range = entityBean.getEntityRange();   // start + range into Range object

// Manual:
Range range = new Range(start, count);
```

---

## Debugging DB Queries

In development mode (`ProductConfiguration.isDevelopmentMode() == true`), `WorkerDataAccess` logs the SQL before executing:

```java
// Automatically logged at INFO level:
// [ DB Query ] : SELECT ... LIMIT 100;
```

Force debug mode: set `development.mode=true` in the application config.
