# Progress

## Status

Contract locked for the BB + LOOPS Trace emitter and `/run-loop` lifecycle instrumentation. Run starts at `contract-locked/build-next`. No emitter code is implemented.

## Done

- [x] Replaced the completed internal contract with the trace-emitter and lifecycle-instrumentation boundary.
- [x] Defined one executable verify command: `bash .loops/verify.sh`.

## In progress

- [ ] Build the LOOPS trace protocol and `/run-loop` instrumentation within the locked contract.

## Blocked / open questions

- BB runtime, plugin implementation, dependency installation, and end-to-end pilot remain outside this LOOPS contract.

## Next

- Implement the trace emitter and lifecycle instrumentation.
