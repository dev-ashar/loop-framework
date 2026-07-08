---
name: run-loop
description: The autonomous loop driver — one invocation runs a task to done. Negotiates the contract (builder proposes, evaluator attacks), then loops builder→evaluator→feed-gap-back with NO per-turn human input until the evaluator returns PASS, iterations run out, or the contract proves wrong. Use for any non-trivial build/refactor/fix you want run start-to-finish. This is what makes LOOPS a loop and not a box of tools.
argument-hint: "<the goal, in one sentence>"
---

# run-loop

> "A prompt is a thing you type once and forget. A loop is a thing that runs while
> you sleep." — Karpathy I

You invoke this **once** with a goal. Everything after the contract approval runs
autonomously. You are the orchestrator (Opus): you dispatch agents, read their
structured returns, decide keep/continue/stop, and write state to disk. You do NOT
read source or write code inside the loop — that is a routing failure.

## The one human gate

There is exactly one place a human speaks: **approving the negotiated contract.**
After that, do not interrupt the loop for a finished-vs-unfinished build. Interrupt
only if the *contract itself* turns out wrong (then re-negotiate). "Full auto to
done" is the chosen default.

## The loop

### 0. Bootstrap state
- Run `run.sh init "<goal>"` (or create `.loops/` from templates) if absent.
- Write `.loops/.running` as the active-run marker.

### 1. Negotiate the contract  (invoke the `contract` skill)
- planner sets the boundary → builder proposes checklist → evaluator attacks →
  iterate on disk until the evaluator has no objections and names the verify command.
- **Gate:** show the converged contract; get the human's single approval.
- Nothing below runs until `.loops/contract.md` is locked.

### 2. Build → grade → repeat  (autonomous)
Loop, iteration `i` from 1 to `max` (default 10, from `feature_list.json`):

1. **Build.** Dispatch `builder` with the contract + (on i>1) the evaluator's GAP
   from the previous round. It implements strictly within the plan/boundary,
   edits in place, returns `BUILT`.
2. **Grade.** Dispatch `evaluator` (fresh context, adversarial): run the verify
   command, walk every criterion, return `REVIEW: PASS|BLOCK`, `SCORE`, `GAP`.
3. **Record.** Overwrite `.loops/progress.md` (iteration, score, what's done/blocked);
   append one line to `.loops/log.md`.
4. **Decide:**
   - `PASS` and guard holds → **break, go to Land.**
   - `BLOCK` → feed `GAP` into the next iteration's builder. Continue.
   - Score regressed or stuck flat for 2 rounds → consider a **restart** (throw the
     work away, rebuild from the contract). A clean restart beats patching
     archaeology; do not fear it.
   - Guard violated (e.g. tests that were passing now fail) → discard this
     iteration's change, feed the violation back as the gap.
   - `max` reached without PASS → stop; report the gap and best score honestly.

### 3. Land
- Final `evaluator` (or `/code-review`) pass over the cumulative diff.
- **Never push/deploy/publish without explicit approval** — that is outside the gate.
- Summarize: what changed · kept vs discarded · final score vs contract · follow-ups.
- Capture a lesson to memory if the run taught one. Remove `.loops/.running`.

## Why this is a loop (and `/contract` alone is not)

Calling a skill each turn is you being the loop. `run-loop` *is* the loop: after one
approval it cycles the roles itself until a stop condition. For purely measurable
goals you can instead hand the locked contract to native **`/goal`** — same idea,
the harness supplies the repetition. Reach for `run-loop` when you want the full
role-separated build/grade cycle; `/goal` when a single metric defines done.

## Do not

- Read files or write code as the orchestrator — dispatch builder/evaluator.
- Let the builder grade its own output — grading is always a fresh evaluator.
- Skip the contract negotiation and jump to building — that's the failure mode.
- Push past `max` iterations silently — surface the gap and stop.
