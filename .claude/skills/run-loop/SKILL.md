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
- Run `loops init "<goal>"` (or create `.loops/` from templates) if absent.
- Write `.loops/.running` as the active-run marker.
- Run `loops trace start --task "<goal>"`; the orchestrator owns every lifecycle event.
- Keep the returned `correlationId` in every `Agent` description.

### 1. Negotiate the contract  (invoke the `contract` skill)
- Emit `contract/awaiting-approval` before the human gate.
- Emit `contract/locked` after approval, with the locked contract hash.
- Builders and evaluators do not emit authoritative lifecycle events or PASS.
- Emit `loop-start`, `role-dispatch`, `role-completion`, `score-recorded`, `repair-requested`, `guard-result`, `loop-BLOCK`, and `loop-end` for each transition.
- planner sets the boundary → builder proposes checklist → evaluator attacks →
  iterate on disk until the evaluator has no objections and names the verify command.
- **Gate:** show the converged contract; get the human's single approval.
- Nothing below runs until `.loops/contract.md` is locked.

### 2. Build → grade → repeat  (autonomous)
Loop, iteration `i` from 1 to `max` (default 10, from `feature_list.json`):

1. **Build.** Emit `role-dispatch` before dispatching. Include the same `correlationId` in the `Agent` description. Dispatch `builder` with exact acceptance criteria, allowed files, and the named verify command. Include the contract + (on i>1) the evaluator's GAP from the previous round. It implements strictly within the plan/boundary, edits in place, returns `BUILT` or `BLOCKED` with `invariants`, `within-plan`, and `verify` evidence. Before evaluator dispatch, run `bash .loops/verify.sh builder-report <report-file>`. Parse it before grading. Treat the report as evidence, not completion. Reject missing fields, malformed invariant evidence, failed criteria, `within-plan: NO`, unnamed verify commands, or a failed or missing verify command. Emit `role-completion` after the return.
2. **Grade.** Emit `role-dispatch` before dispatching. Include the same `correlationId` in the `Agent` description. Dispatch a fresh `evaluator` context (adversarial): run the verify command, walk every criterion, and return `REVIEW: PASS|BLOCK`, `SCORE`, `GAP`. Emit `role-completion` after the return. Pass the raw builder report as advisory evidence only. Evaluator cannot write authoritative trace state or delegate grading.
3. **Record.** Overwrite `.loops/progress.md` (iteration, score, what's done/blocked); append one line to `.loops/log.md`.
   Run `loops score record <i> <score> <verdict>` to persist the iteration result. Emit `score-recorded` with the score and verdict.
   Run `loops score stall`; emit `guard-result` with the exit status. Exit code 2 means the score stalled — emit `repair-requested` and trigger a restart.
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
- Do not emit a `loop-PASS` trace event. The UI derives PASS only from evaluator PASS, successful guard result, and the locked contract hash.
- Emit `loop-BLOCK` when the evaluator blocks or a guard fails.
- Final `evaluator` (or `/code-review`) pass over the cumulative diff.
- **Never push/deploy/publish without explicit approval** — that is outside the gate.
- Summarize: what changed · kept vs discarded · final score vs contract · follow-ups.
- Record the run: `loops mem note "<what the loop built or ruled out>"`. Add
  `loops mem fact "<text>"` for anything the next agent would otherwise re-derive.
  Emit `loop-end`, then run `loops trace end` and remove `.loops/.running`.

### Parallel builders

When the locked plan has at least two builder steps over disjoint file sets, the orchestrator provisions one worktree per step and dispatches that many `builder` agents in a single message. It runs `scope-check` for each worktree, then merges each branch with `git merge --no-ff` before the evaluator grades. The merge stops at the first conflict, names the conflicting branch, and does not auto-abort. With exactly one builder step, no worktree is provisioned and `builder` is dispatched in place exactly as today; this single-builder path is ceremony-free.

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
