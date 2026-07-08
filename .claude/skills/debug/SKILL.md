---
name: debug
description: Triage and reproduce a bug before fixing it — including live infra (k8s pods, redis). Use when given an error, failing test, or production symptom. Enforces reproduce-first, root-cause-not-symptom.
---

# debug

> Every debugging insight comes from reading the trace, not from guessing. Find the
> exact moment behavior diverged, then fix that moment.

## Reproduce first (the gate)

Do not touch code until you can reproduce the failure on demand. A bug you can't
reproduce is a bug you can't verify you fixed. Capture the minimal repro command
and put it in `.loops/contract.md` as the verify command.

## Read the trace

- Get the real error: full stack trace, not the summary. Pipe long output to a file
  and grep for the first divergence, not the final symptom.
- Bisect: what's the smallest input / most recent change that triggers it?

## Live infra (k8s / redis)

- **Pods:** `kubectl logs <pod> -n <ns>` (add `--previous` for crashloops),
  `kubectl describe pod` for events/OOM/restart counts, `kubectl exec` to inspect
  from inside. Check resource limits before assuming a code bug.
- **Redis:** `redis-cli` — inspect keys/TTLs/memory; `MONITOR` briefly to see live
  traffic; check for evictions and connection saturation.
- Treat live systems read-only unless the fix is explicitly authorized. Never flush
  or restart without saying so.

## Root cause, not symptom

- State the causal chain: input → what happened → why → the actual defect.
- Fix the cause. A retry/try-except that hides the error is not a fix.
- Add a regression check so the bug can't silently return.

## Verify

Re-run the repro command. It must now pass. Then run the surrounding suite to
confirm you didn't fix one thing and break another. Log the root cause in `.loops/log.md`.

## Do not

- Patch symptoms because the root cause is hard to find.
- Declare fixed without re-running the exact repro.
- Mutate production state to "test" a theory.
