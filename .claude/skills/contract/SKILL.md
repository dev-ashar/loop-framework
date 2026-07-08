---
name: contract
description: Negotiate a testable contract of acceptance criteria BEFORE any code is written — as an adversarial argument between the builder (proposes "done") and the evaluator (attacks it), iterating on disk until no objections remain. Use at the start of any non-trivial build, refactor, or debugging campaign. Produces .loops/contract.md, the boundary the evaluator later grades against.
---

# contract

> "The generator proposes what done looks like and the evaluator pushes back. The
> two argue via markdown files on disk until they agree on a checklist of testable
> assertions. Ten is usually too few and the evaluator rubber-stamps." — Karpathy III

The contract is **not** written by one agent. It is *negotiated* between two, so no
single context both defines and grades "done." This adversarial argument is the
single change that moves runs from broken demos to working products.

## Roles in the negotiation

- **planner** sets the **boundary** — goal, constraints, non-goals. This is the
  spec; it does not change during negotiation. (Dispatch the `planner` agent, or
  seed it from `run.sh init "<goal>"`.)
- **builder proposes** the acceptance checklist — what *it* claims proves the goal
  is met, within the boundary.
- **evaluator attacks** the checklist — flags every criterion that is vague,
  untestable, rubber-stampable, or missing. It wants criteria it cannot fake.
- **you** approve the converged contract, and are the tiebreaker *only* if the
  boundary itself is wrong.

The orchestrator (Opus) relays between agents via the file on disk and never writes
the criteria itself.

## Protocol

1. **Boundary.** Ensure `.loops/contract.md` exists (`run.sh init "<goal>"`).
   Dispatch `planner` to fill Goal / Constraints / Non-goals from the goal +
   codebase (via `explorer`). This is the fixed frame.

2. **Propose.** Dispatch the `builder` agent: *"Propose the acceptance checklist
   for this goal — the testable assertions that would prove it's done. Each must be
   checkable by running something. Write them into `.loops/contract.md`."*

3. **Attack.** Dispatch the `evaluator` agent: *"You will later have to grade
   against this checklist and you want it airtight. Attack it. For each criterion:
   is it testable by running something? Could you rubber-stamp it? What's missing?
   Write your objections to `.loops/contract.md` under an OBJECTIONS heading. Do NOT
   soften anything."*

4. **Iterate.** Relay the objections back to `builder` to revise. Repeat 2–3 until
   the evaluator returns **no objections** — a checklist of concrete, runnable
   assertions (aim well past ten; ten rubber-stamps). Keep the argument trail in
   `.loops/contract.md` (or `.loops/contract-negotiation.md`) — it's a trace.

5. **Verify command.** The evaluator states the exact command(s) it will run to
   grade. It must emit observable results. Dry-run it once to confirm.

6. **Lock.** Show the converged contract. On your approval it becomes the boundary.
   From here the loop runs; a human interrupts only if the *contract* is wrong —
   never because the *build* is unfinished.

## Handoff

The locked contract feeds:
- **`run-loop`** — the autonomous driver that builds and grades against it,
- native **`/goal`** — verify command becomes the stop condition,
- the **`evaluator`** agent — which grades against nothing but this file.

## Do not

- Let the agent that will build the thing also grade its own criteria unchallenged.
- Accept a checklist the evaluator didn't try to break.
- Write criteria checkable only by reading. If you can't run it, it's not a criterion.
