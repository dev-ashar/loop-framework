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
  seed it from `loops init "<goal>"`.)
- **builder proposes** the acceptance checklist — what *it* claims proves the goal
  is met, within the boundary.
- **evaluator attacks** the checklist — flags every criterion that is vague,
  untestable, rubber-stampable, or missing. It wants criteria it cannot fake.
- A fresh evaluator reviews the final contract before approval.
- Only an explicit host-conversation response approves the exact final contract hash.
  Local records are advisory and cannot prove approval.
- Contract changes invalidate approval and require fresh host approval.

Each planner, builder, and evaluator returns a structured proposal or attack. The
orchestrator integrates accepted content and writes authoritative contract state.
Agents never write `.loops/contract.md` or other authoritative state.

## Protocol

1. **Boundary.** Ensure `.loops/contract.md` exists (`loops init "<goal>"`).
   Always dispatch `explorer` first and wait for completion. For production-data
   incidents, require the explorer to run the cheapest decisive read-only direct
   check when access exists before planning or expanding theory. For object-freshness
   incidents, enumerate candidate relations and compare latest timestamps and state.
   Reject plan-only returns when executable evidence was requested. Any retry must
   change the method or route. Urgent work without a build uses the minimal
   explorer-only investigation. Dispatch `planner` only when the boundary is unclear,
   and record the written reason before that call.
   The planner proposes Goal / Constraints / Non-goals from the goal, explorer
   findings, and codebase. The orchestrator writes authoritative state. Run
   `loops lesson check "<goal keywords>"` first — a hit tagged
   `external-data-source` means this ground was already burned once. When the goal
   names an external API or data source, require a mandatory acceptance criterion
   of the form "verify <external system>'s exact semantics via a live read-only
   check before locking". This is the fixed frame.

2. **Propose.** For nontrivial work, dispatch the `builder` only after exploration.
   Return a structured acceptance checklist. Each assertion must be testable.
   The orchestrator integrates the proposal into `.loops/contract.md`.

3. **Attack.** Dispatch a newly created, fresh `evaluator` context.
   Return a structured attack for every criterion. Check testability, omissions,
   and false passes. The evaluator reviews the final contract before approval.

4. **Iterate.** Dispatch a newly created, fresh evaluator context for every attack
   round. Relay structured objections to the builder, then integrate returned
   revisions and attacks through the orchestrator. Repeat 2–3 until the evaluator
   returns **no objections**. Keep the argument trail in `.loops/contract.md` or
   `.loops/contract-negotiation.md` as orchestrator-owned trace state.

5. **Verify command.** The evaluator states the exact command(s) it will run to
   grade. It must emit observable results. Dry-run it once to confirm.

6. **Lock.** Validate the contract with `run.sh lint .loops/contract.md`.
   Any lint failure blocks approval. Compute the exact contract hash after evaluation.
   Ask the host user to approve that exact final contract. Local observations are
   advisory only. A changed hash requires fresh evaluation and host approval.
   Lock only after explicit host approval. Repairs within the approved contract do
   not require reapproval. If evidence disproves the contract, renegotiate and obtain
   approval again within the original goal.

## Handoff

The locked contract feeds:
- **`run-loop`** — the autonomous driver that builds and grades against it,
- native **`/goal`** — verify command becomes the stop condition,
- the **`evaluator`** agent — which grades against nothing but this file.

## Do not

- Let the agent that will build the thing also grade its own criteria unchallenged.
- Accept a checklist the evaluator didn't try to break.
- Write criteria checkable only by reading. If you can't run it, it's not a criterion.
