# Contract — architecture migration

## Goal

Replace the schemaVersion 2 job runtime with architect-owned contract semantics.

## Constraints

- Keep installer rollback behavior.
- Keep dispatch, agent, profile, schema, runtime, documentation, and test routing consistent with the authorized model matrix.
- Keep validated DAG input and scope isolation.
- Remove trace, envelope, and report requirements from runtime execution.

## Architecture

- The architect owns contract meaning, acceptance, and integration decisions.
- The runtime validates DAG structure and execution facts only.
- Independent builder jobs run in parallel.
- Each declared lens identifies an independent review concern.
- Reconciliation reports confirmed or unknown live state without creating a gate.
- Dependencies require completed work, not a fixed integration sequence.
- Installer rollback remains unchanged.

## Acceptance criteria

1. `run.sh trace` exits nonzero with a retirement diagnostic.
2. Runtime execution does not call approval, envelope, or report validators.
3. Runtime records declared review lenses after each successful worker job.
4. Independent ready jobs dispatch concurrently.
5. Lifecycle readiness accepts passed or integrated dependencies.
6. Reconciliation emits neutral confirmed or unknown outcomes.
7. `.loops/verify.sh` runs focused job suites and syntax checks.
8. Installer rollback code remains present and unmodified.

## Verify

```bash
bash tests/job-framework.sh
bash tests/job-executor.sh
bash tests/job-dispatch.sh
bash tests/job-integration.sh
bash tests/job-lifecycle.sh
bash tests/job-runtime.sh
bash .loops/verify.sh
bash -n run.sh lib/job-*.sh
```
