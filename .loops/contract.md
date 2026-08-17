# Contract — BB + LOOPS Trace emitter and run-loop instrumentation

Locked 2026-08-17. Graded by `evaluator` against this file only.

## Goal

Add a read-only LOOPS trace protocol and `/run-loop` lifecycle instrumentation for BB integration. The emitter records authoritative LOOPS transitions without allowing agents or BB to own loop state.

## Constraints

- Modify only the LOOPS CLI, `/run-loop` skill, tests, documentation, and contract artifacts for this phase.
- Keep the trace file transient at `.loops/trace.jsonl` and keep it gitignored.
- Keep LOOPS as the only owner of the contract, iteration state, evaluator verdict, score, gap, and PASS.
- Keep the BB plugin, BB runtime, UI, dependency installation, and end-to-end pilot outside this contract.
- Keep evaluator and builder agents unable to write authoritative trace state directly.
- Do not add compatibility shims or change unrelated behavior.
- Do not write secrets or ambient BB state into the LOOPS repository.

## Acceptance criteria

> Each assertion is checked by running `.loops/verify.sh` and its named fixture or probe. A failing assertion returns non-zero.

1. `bash .loops/verify.sh` confirms that the CLI exposes `loops trace start`, `loops trace emit`, and `loops trace end` (or one documented equivalent command family), and rejects an unknown trace subcommand with a non-zero status.
2. The trace start probe creates exactly one run identifier and an append-only `.loops/trace.jsonl` file without modifying the locked contract or durable loop state.
3. Every emitted JSONL record contains `schemaVersion`, `eventId`, `runId`, `sequence`, `timestamp`, `iteration`, `role`, `phase`, `status`, `correlationId`, and the locked-contract hash.
4. Optional score, verdict, gap, task identifier, and worktree metadata fields are omitted when absent and preserved when supplied.
5. The JSONL probe parses every record as one complete JSON object, rejects malformed input with a non-zero status, and never writes a partial JSON object.
6. The sequence probe shows strictly increasing integer sequence values within one run, including after a process restart or an append recovery.
7. The event probe shows unique event identifiers within one run and deterministic rejection of duplicate event identifiers.
8. The timestamp probe accepts only valid machine-readable timestamps and records the timestamp at emission time.
9. The contract-hash probe derives the hash from the locked contract bytes, records the same hash on every event, and changes the hash after a contract-byte mutation.
10. The hash-mismatch probe prevents a PASS event when the event hash differs from the currently locked contract hash.
11. The transition probe records loop start, contract awaiting approval, contract locked, role dispatch, role completion, score recorded, repair requested, guard result, loop PASS or BLOCK, and loop end in append order.
12. The approval-gate probe records contract awaiting approval and blocks builder dispatch until the contract is approved and locked.
13. The correlation probe puts one run correlation identifier in every Claude Agent description created by the orchestrator and links those descriptions to the matching trace run.
14. The authority probe proves that builder and evaluator processes can emit observations only through the orchestrator and cannot forge an authoritative PASS, score, verdict, or contract hash.
15. The negative PASS probe proves that an agent-supplied PASS record is ignored or rejected and cannot change the LOOPS verdict.
16. The role probe distinguishes planner, builder, evaluator, and orchestrator roles in emitted records without collapsing them into a generic agent role.
17. The iteration probe records the active iteration on every transition and preserves iteration changes across a BLOCK-to-repair cycle.
18. The append probe proves that a second emission appends one line, preserves all earlier bytes, and does not rewrite or reorder existing records.
19. The malformed-record probe handles missing required fields, wrong field types, unknown status values, and invalid correlation identifiers with deterministic non-zero results.
20. The recovery probe handles an interrupted final line by discarding only the incomplete tail, then resumes with the next monotonic sequence value.
21. The lifecycle probe emits loop end for both PASS and BLOCK terminal paths and never treats provider completion or BB idle state as LOOPS PASS.
22. The existing LOOPS verification suite remains green after trace instrumentation is enabled.
23. The trace protocol tests cover monotonic sequences, valid JSONL, event uniqueness, contract hashing, malformed inputs, truncation recovery, and replacement handling.
24. The trace path is ignored by Git, and the trace probe confirms that no `.loops/trace.jsonl` bytes enter a normal repository diff.
25. The documentation probe identifies the trace schema, lifecycle transitions, authority boundary, transient-file rule, and the single supported emitter entrypoint.
26. The final guard probe returns non-zero when any required transition, required field, correlation identifier, contract hash, or authority check is missing.

## Verify command

```bash
bash .loops/verify.sh
```
