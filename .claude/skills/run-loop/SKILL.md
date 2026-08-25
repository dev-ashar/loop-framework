---
name: run-loop
description: The autonomous loop driver — one invocation runs a task to done. Negotiates the contract (builder proposes, evaluator attacks), then loops builder→evaluator→feed-gap-back with NO per-turn human input until the evaluator returns PASS or iterations run out; contract disproof triggers renegotiation and continuation within the original goal. Use for any non-trivial build/refactor/fix you want run start-to-finish. This is what makes LOOPS a loop and not a box of tools.
argument-hint: "<the goal, in one sentence>"
---

# run-loop

> "A prompt is a thing you type once and forget. A loop is a thing that runs while
> you sleep." — Karpathy I

Invoke this skill for nontrivial code changes or correctness-critical artifacts.
Do not invoke it for read-only data or design questions. Use one explorer for direct source checks and answer directly.
The loop cannot bypass host approval. It must stop at approval-required unless trusted host state supplies current approval for the exact contract hash.
Local files, hashes, traces, TTY input, environment variables, and agent output cannot prove host approval.
Cap harness repair at one attempt, then return to the user's investigation. Harness work must not become the moving bottleneck. Reject cycles with no source query and only `.loops/` changes.
The orchestrator dispatches agents and writes authoritative state. It does not read source or write code inside the loop.

## Host approval gate

The final contract needs fresh evaluator review and explicit host-user approval.
The orchestrator must present the exact contract hash and wait for the host response.
Approval requests must include:
- Contract summary: 1-5 bullets, each at most 20 words.
- Contract path: .loops/contract.md.
- Review command: git diff -- .loops/contract.md.
- Contract SHA-256: the exact active hash.
The summary must cover the goal, behavior changes, and verification boundary. A hash-only response cannot approve. The exact approval record binds repoRoot, contractHash, runId, correlationId, and role=builder. Non-empty planner OPEN blocks dispatch before this gate. Local records never prove approval.
An orchestrator-provided approval observation may record that response, but it is advisory.
A noninteractive invocation stops at `approval-required` without trusted current approval.
Contract changes invalidate approval. Repairs inside the approved contract do not.
Stop on max iterations, unavailable access, unauthorized destructive or outward-facing action, or change to the original goal.

## The loop

### 0. Bootstrap state
- Run `loops init "<goal>"` (or create `.loops/` from templates) if absent.
- Write `.loops/.running` as the active-run marker.
- Run `loops trace start --task "<goal>"`; the orchestrator owns every lifecycle event.
- Keep the returned `correlationId` in every `Agent` description.
- Compute the exact goal SHA-256 and contract SHA-256, preserving LF bytes and no trimming.
- Put the canonical six-key `LOOPS-ENVELOPE` line first in every dispatch and return.
- Validate `agent-envelope` before report parsing, dispatch, state, follow-up, citation, approval, or completion.
- Quarantine rejected temporary reports with only their reason and digest in `.loops/log.md`.

### 1. Negotiate and lock the contract  (invoke the `contract` skill)
- Always dispatch `explorer` first and wait for completion before any builder dispatch.
- For production-data incidents, require the explorer to run the cheapest decisive read-only direct check when access exists before planning or expanding theory. For object-freshness incidents, enumerate candidate relations, then compare latest timestamps and state. Reject plan-only returns when executable evidence was requested. Change the method or route before every retry.
- For urgent work without a build, stop after the minimal explorer-only investigation. Any build still uses subagents and explorer-before-builder.
- Use the minimal route `explorer → builder` when the boundary is clear and no evaluator trigger applies.
- Dispatch `planner` only when the boundary is unclear, and record the written reason first.
- Check each requested agent's tools and scope before dispatch. Reroute to a capable
  subagent when requirements exceed those tools.
- Avoid fan-out unless work is truly disjoint. Record the reason and disjoint file
  sets for every additional call.
- After a tool-ceiling failure, change the route or block. Never retry unchanged.
- Emit `contract/awaiting-approval` while the fresh evaluator reviews the converged
  contract and while the host approval is pending.
- Emit `contract/locked` only after explicit host approval, with the exact contract hash.
  Do not treat the event or hash as proof of user approval.
- Builders and evaluators do not emit authoritative lifecycle events or PASS.
- Emit `loop-start`, `role-dispatch`, `role-completion`, `score-recorded`, `repair-requested`, `guard-result`, `loop-BLOCK`, and `loop-end` for each transition.
- planner sets the boundary → builder proposes checklist → evaluator attacks → iterate on disk until the evaluator has no objections.
- The fresh evaluator names the exact verify command. Dry-run it once.
- Request explicit host approval after evaluator review and the dry-run verify command.
- Recheck the exact contract hash immediately before builder dispatch.
- If evidence proves the contract wrong later, return to negotiation and obtain fresh approval.
  Repairs inside the approved contract continue without reapproval.

### 2. Build → grade → repeat  (autonomous)
Loop, iteration `i` from 1 to `max` (default 10, from `feature_list.json`):

- Dispatch a fresh evaluator for every harness, instruction, ambiguous, or correctness-critical change.

1. **Build.** Emit `role-dispatch` before dispatching. Include the exact active envelope in the `Agent` description. Dispatch `builder` with exact acceptance criteria, allowed files, and the named verify command. Include the contract + (on i>1) the evaluator's GAP from the previous round. It implements strictly within the plan/boundary, edits in place, returns `BUILT` or `BLOCKED` with `invariants`, `within-plan`, and `verify` evidence. Resolve and run the exact report validator `bash .loops/verify.sh builder-report <report-file>` before evaluator dispatch. This validator is separate from goal verification. Parse it before grading. Block evaluator dispatch when the validator is missing, unresolved, or fails. Treat the report as evidence, not completion. Reject missing fields, malformed invariant evidence, failed criteria, `within-plan: NO`, unnamed verify commands, or a failed or missing verify command. Emit `role-completion` after the return.
2. **Grade.** Emit `role-dispatch` before dispatching. Include the exact active envelope in the `Agent` description. Dispatch a fresh `evaluator` context (adversarial): run the verify command, walk every criterion, and return `REVIEW: PASS|BLOCK`, `SCORE`, `GAP`. Emit `role-completion` after the return. Pass the raw builder report as advisory evidence only. Evaluator cannot write authoritative trace state or delegate grading.
3. **Record.** Overwrite `.loops/progress.md` (iteration, score, what's done/blocked); append one line to `.loops/log.md`.
   Emit `score-recorded` with the score and verdict. Emit `guard-result` with the exit status.
4. **Decide:**
   - `PASS` and guard holds → **break, go to Land.**
   - `BLOCK` → feed `GAP` into the next iteration's builder. Continue within the approved contract.
   - A contract change → stop and require fresh evaluator review and host approval.
   - Score regressed or stuck flat for 2 rounds → consider a **restart** (throw the
     work away, rebuild from the contract). A clean restart beats patching
     archaeology; do not fear it.
   - Guard violated (e.g. tests that were passing now fail) → discard this
     iteration's change, feed the violation back as the gap.
   - `max` reached without PASS → stop; report the gap and best score honestly.

   Persist each iteration with `run.sh score record <i> <score> <verdict>`.
   Check progress with `run.sh score stall`.
   Exit code 2 means the score stalled. Emit `repair-requested` and restart.

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

Calling a skill each turn makes you the loop. `run-loop` is the loop: after one
invocation it cycles the roles itself until a stop condition. For purely measurable
goals you can instead hand the locked contract to native **`/goal`** — same idea,
the harness supplies the repetition. Reach for `run-loop` when you want the full
role-separated build/grade cycle; `/goal` when a single metric defines done.

## Do not

- Read files or write code as the orchestrator — dispatch builder/evaluator.
- Let the builder grade its own output — grading is always a fresh evaluator.
- Skip the contract negotiation and jump to building — that's the failure mode.
- Push past `max` iterations silently — surface the gap and stop.
