# Test Patterns Reference

## Test Location and Structure

```
test/com/qntrl/circuit/
  util/          # Utility class tests (CircuitReplaceUtilTest, JsonPathUtilTest, ParserUtilTest, etc.)
  config/        # Configuration tests
  schema/        # JSON schema tests
  jsonmasker/    # JsonMasker tests
  context/       # IOContext tests
```

## Test Framework

- **JUnit 5** (`@Test`, `@DisplayName`, `@BeforeEach`, `@BeforeAll`, `@ParameterizedTest`)
- **Assertions:** `org.junit.jupiter.api.Assertions.*` (`assertEquals`, `assertTrue`, `assertFalse`, `assertNull`, `assertNotNull`, `assertThrows`)
- **Gson** for JSON construction in tests
- No Spring context, no Mockito (tests are pure unit tests against utility classes)

## Naming Convention

```java
@DisplayName("ClassName Tests")        // class-level
@DisplayName("methodName - scenario")  // method-level
public class XxxTest {
    @Test
    public void testMethodName_scenario() { ... }
}
```

## Observed Test Shape (from CircuitReplaceUtilTest)

```java
package com.qntrl.circuit.util;

import com.google.gson.*;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import java.util.HashMap;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;

@DisplayName("CircuitReplaceUtil Tests")
public class CircuitReplaceUtilTest {

    private static final Gson GSON = new Gson();

    // Use private constants for fixtures — keeps test methods short and readable
    private static final String CIRCUIT_CONFIG = "{ ... }";

    @Test
    @DisplayName("replaceIntegrationId - replaces all matching integration IDs")
    public void replaceIntegrationId_allMatching() {
        // Arrange
        Map<Long, Long> idMap = new HashMap<>();
        idMap.put(117418553L, 999L);

        // Act
        String result = CircuitReplaceUtil.replaceIntegrationId(CIRCUIT_CONFIG, idMap);

        // Assert
        JsonObject json = GSON.fromJson(result, JsonObject.class);
        // ... assertions
        assertEquals(999L, actualId);
    }

    @Test
    @DisplayName("replaceIntegrationId - does not modify non-matching IDs")
    public void replaceIntegrationId_noMatch() {
        Map<Long, Long> idMap = new HashMap<>();
        idMap.put(99999L, 1L);  // ID not in config

        String result = CircuitReplaceUtil.replaceIntegrationId(CIRCUIT_CONFIG, idMap);
        // Config should be unchanged
        assertEquals(CIRCUIT_CONFIG, result);
    }
}
```

## Key Patterns

### Testing IOContext

```java
import com.qntrl.circuit.context.IOContext;

// Create from JSON string
IOContext ctx = new IOContext("{\"name\": \"test\", \"count\": 5}");

// Read values
String name = ctx.get("$.name", String.class);
int count = ctx.get("$.count", Integer.class);

// Evaluate condition
assertTrue(ctx.evaluateCondition("$.count > 3"));
assertFalse(ctx.evaluateCondition("$.count > 10"));

// Put value
ctx.put("$.newField", "value");
```

### Testing JSON Schema Validation

```java
// Schemas live in resources or are built inline
// Use JsonSchemaUtils.validate() for validation tests
```

### Testing JsonMasker

```java
// JsonMaskerBundle wraps masking logic per state
// Test by constructing a bundle with a mocked/stub StateEntity and calling mask()
```

## Test Fixture Construction

Use string literals for circuit config JSON (as seen in CircuitReplaceUtilTest). For Gson deserialization:

```java
private static final Gson GSON = new Gson();

// Parse as JsonObject
JsonObject json = GSON.fromJson(jsonString, JsonObject.class);

// Build JsonObject programmatically
JsonObject obj = new JsonObject();
obj.addProperty("key", "value");
obj.addProperty("count", 5);
JsonArray arr = new JsonArray();
arr.add("item1");
obj.add("list", arr);
```

## What NOT to Test

- Do not test DB access in unit tests — no mock DB, no Mockito
- Do not start a Spring/Struts context in tests
- Do not test actor behavior directly — actors require the full Akka/Reactor runtime
- Focus tests on: utility methods, JSON manipulation, schema validation, context operations, parsers

## Build Integration

Tests are compiled and run via Ant. The test classpath must include the test output directory and all dependencies. Compilation errors in source files will prevent tests from running.

To check that your new class compiles correctly against existing dependencies, read the existing imports in nearby files and ensure your new code uses the same pattern.

## Adding a New Test File

1. Create `test/com/qntrl/circuit/<subpackage>/XxxTest.java`
2. Package must be `com.qntrl.circuit.<subpackage>`
3. Use `@DisplayName` on the class
4. Each `@Test` method should be independently runnable (no shared mutable state)
5. Use constants for fixtures — avoid constructing complex JSON inline in test methods
