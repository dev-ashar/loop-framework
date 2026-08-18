# Contract — LOOPS trace protocol

Locked 2026-08-17. Graded by `evaluator` against this file only.

## Goal

Add a durable, append-only LOOPS trace protocol and orchestrator lifecycle instrumentation.

## Constraints

- Keep trace records transient and gitignored under `.loops/trace.jsonl`.
- Keep the contract hash locked for each active run.
- Keep evaluator and builder agents unable to write authoritative trace state.
- Never emit a PASS status or verdict from the trace CLI. Derive authoritative PASS in the UI from an evaluator PASS verdict, a successful guard event, and the locked contract hash.
- Do not alter unrelated CLI behavior.

## Acceptance criteria

1. `run.sh trace start`, `run.sh trace emit`, `run.sh trace end`, and `run.sh trace validate` exist, print usage for invalid calls, and return non-zero on invalid input.
2. Each trace line is strict JSONL with exactly the required fields `schemaVersion`, `eventId`, `runId`, `sequence`, `timestamp`, `iteration`, `role`, `phase`, `status`, `correlationId`, and `contractHash`; optional fields are `score`, `verdict`, `gap`, `task`, and `worktree`.
3. Trace records append to `.loops/trace.jsonl`, which is gitignored. Sequence values increase from one without gaps, and event IDs are unique.
4. A trace start stores the SHA-256 hash of `.loops/contract.md`. Emission rejects malformed records and rejects a changed contract hash.
5. Malformed JSON, unknown fields, missing fields, invalid types, duplicate IDs, non-monotonic sequences, and mismatched run or correlation IDs return non-zero without appending.
6. The trace CLI rejects every PASS status and PASS verdict. Consumers derive UI PASS from an evaluator PASS verdict, a successful guard event, and the locked contract hash.
7. `run-loop` documents orchestrator-owned lifecycle emissions for loop start, contract awaiting approval, contract locked, role dispatch, role completion, score recorded, repair requested, guard result, loop PASS/BLOCK, and loop end.
8. `run-loop` requires the same `correlationId` in every `Agent` description and prohibits builder/evaluator authority over trace state.
9. `.loops/verify.sh` mechanically tests schema validation, malformed payload rejection, uniqueness, monotonic sequence, contract hashing, gitignore state, and forged PASS rejection.
10. `bash -n run.sh lib/trace.sh` passes, and `bash .loops/verify.sh` passes.

## Verify command

```bash
bash .loops/verify.sh
```
