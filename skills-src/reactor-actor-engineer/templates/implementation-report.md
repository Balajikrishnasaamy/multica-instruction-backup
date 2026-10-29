# Implementation report template

Fill this after every reactor task. Prefer YAML so CirDoc/orchestrators can parse it.

```yaml
result:
  status: completed # completed | blocked | failed

  summary: ""

  root_cause: ""

  implementation:
    files_changed:
      - path: ""
        reason: ""

  verification:
    commands:
      - command: "bash <skill folder>/scripts/verify.sh"
        result: pass # pass | fail | skipped
      - command: "bash <skill folder>/scripts/test-nonsharded.sh"
        result: pass
      - command: "bash <skill folder>/scripts/test-sharded.sh"
        result: pass
      # Optional full product build (heavy; needs ANT_HOME/JAVA_HOME):
      # - command: "VERIFY_COMPILE=1 bash <skill folder>/scripts/verify.sh"
      #   result: pass
      # Exact underlying ant: bash build/local_build/run.sh → ant -Dpdt_name=qntrlworker
    build: pass # pass | fail | skipped
    unit_tests: skipped # no JUnit reactor suite in this repo
    integration_tests: skipped # no reactor integration suite in this repo
    notes: |
      HTTP /testing covers ScriptWorker/Qntrl/IoT/load only — not reactor.
      ExecutionLoadMetricsSmokeTest.run() is live-worker metastore smoke only.

  architecture_impact:
    sharding: none # none | low | medium | high
    persistence: none
    actor_lifecycle: none

  acceptance:
    - criterion: ""
      evidence: ""

  review:
    concerns: []

  remaining_risks: []

  sharding_modes_considered:
    - true
    - false

  persistence_journal_compatibility: held # held | risk | unknown

  stop_reason: "" # set when status is blocked/failed
```

## Short prose appendix (optional)

- Findings table (analysis): `File:Line | Severity | Fix`
- Diff risk note: sharding? journal? inheritance?
