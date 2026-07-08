# CLAUDE.md — the LOOPS contract

Most agent systems die from a weak harness, not a weak model. This file is the
harness, kept deliberately thin. Re-read it against each model release and delete
anything the model now does for free.

## The loop

Every task is one loop: **gather → reason → act → verify → repeat.** Everything
below is a footnote on those five verbs.

## The nine rules

1. **Write the loop, not the prompt.** The procedure is the unit of leverage.
2. **Separate the roles.** planner ≠ builder ≠ evaluator. Never let the generator
   grade its own work — that is where loops converge on slop.
3. **Negotiate the contract first.** Before code, agree on testable acceptance
   criteria (`/contract` → `.loops/contract.md`). That file is what gets graded.
4. **Write to disk, not to context.** State lives in `.loops/`, not the window.
5. **Let the loop restart.** A clean restart from the contract beats patching
   archaeology. Interrupt only when the *contract* is wrong, not when the build is.
6. **Score the subjective.** Taste is gradable if you write the rubric (`/taste`).
7. **Read the traces.** Debug from `.loops/log.md`, not by re-running blind.
8. **Delete the harness.** Half of what helped last quarter is overhead now.
9. **The bottleneck always moves.** Coding → planning → verification → taste. Find
   the next one; ship a smaller harness.

## Routing (the one rule)

**Opus = this session, and only orchestrates**: plan, judge, synthesize, decide.
The Opus-tier thinking happens *inline here* — deciding the approach, reading the
subagents' structured returns, judging them, deciding keep/next/stop. You never
delegate that thinking to a cheaper model, and you never spin up an Opus subagent
for it either. What you delegate is **volume**, at the cheapest competent tier:
`explorer` (Haiku) to find/map, `builder` (Sonnet) to write code, `planner`
(Sonnet) to draft the contract, `evaluator` (Sonnet, adversarial) to grade against
the contract. The evaluator runs in its own context only so the builder can't grade
itself; its honesty comes from the adversarial prompt + testable contract, and you
review its grade here. Opus reading a file inside a loop is a routing failure —
consume the structured returns; never re-read what they already reported.

## The ladder (there is one loop)

Every task is the same loop — `gather → reason → act → verify`. What changes is
how much of the driving you hand off. Climb only as high as the task needs.

1. **Default — turn-based (no command).** This is the everyday posture, not a mode
   you invoke. Do the task in one cycle and verify before declaring done. Delegate
   anything that means reading source or writing code to an agent (`explorer` /
   `builder`) so the file-heavy work lives in *its* context window, not this
   session's. Covers trivial and small work. Hand off: the *check*.
2. **`/run-loop` — hand off the repetition.** For non-trivial / ambiguous /
   correctness-critical / long-running work: negotiate a contract, then loop
   build→grade until PASS. Hand off: the *stop*.
3. **`/goal` (native) — hand off the stop condition** when a single metric defines done.
4. **`/loop`, `/schedule` (native) — hand off the trigger** for recurring work.

**Auto-escalate with a heads-up.** Start at the default. If a task reveals itself
as bigger than one clean pass — multi-file, ambiguous, correctness-critical — say
so, then climb to `/run-loop` rather than forcing a one-shot. Don't over-build the
small stuff; don't under-build the risky stuff.

Separate context windows come from *agents*, not skills — so your session stays
clean at every rung: delegate the reading, consume the summary.

## State on disk (recoverable from 3 files)

Per project, under `.loops/`:
- `contract.md` — the graded boundary (goal, constraints, acceptance, verify cmd)
- `progress.md` — current state, overwritten each iteration
- `log.md` — append-only trace (`## [YYYY-MM-DD HH:MM] op | title`)
- `feature_list.json` — the metric, for measurable `/goal` runs

If you cannot describe the run in those files, the state is too complicated.

## Loop primitives

- **`/run-loop "<goal>"`** — the autonomous driver. One invocation: negotiate the
  contract, then loop builder→evaluator→feed-gap-back until PASS. This is the loop.
- **`/contract`** — negotiate acceptance criteria as a builder-vs-evaluator argument
  on disk, before any code (rule 2 + 3). Runs inside `run-loop`, or standalone.
- **`/verify`, `/taste`** — encoded end-to-end and subjective checks.
- **`/goal`** — measurable loop with a stop condition (native); hand it a locked contract.
- **`/loop`, `/schedule`** — recurring / scheduled triggers (native).
- **`Workflow`** — fan-out + adversarial verify (native).
- **`/code-review`** + `evaluator` — second-agent review.

A skill called each turn is *you* being the loop. `/run-loop` and `/goal` run the
cycle themselves after one approval — that is the difference between a loop and a
box of tools.

## Memory

Persistent file memory lives in the per-project `.../memory/` dir with a
`MEMORY.md` index (one line per fact). Save `user` / `feedback` / `project` /
`reference` facts that aren't derivable from code or git. After any correction,
capture the lesson. Don't duplicate what the repo already records.

@RTK.md
