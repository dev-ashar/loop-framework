---
name: verify
description: Verify a change actually does what it should by exercising it end-to-end and observing behavior — not just reading the diff or trusting tests. Use before declaring any non-trivial change done. Encodes the gather→act→verify→repeat loop so work is self-checking.
---

# verify

> Context windows lie; a running program does not. If you did not run it, it is not verified.

This is the turn-based verification spine. It makes a change **self-checking**: the
loop does not hand back work until it has driven the change and observed it working.

## Protocol

1. **Locate the surface.** What did the change touch, and how does a human exercise
   it? A page, a CLI command, an API endpoint, a notebook cell, a query.
2. **Drive it.** Actually run the affected flow end-to-end:
   - **App/UI** → start the dev server, open the page, interact, screenshot
     before/after, check the browser console for new errors/warnings.
   - **CLI/service** → run the command / hit the endpoint with real input, inspect output.
   - **Data** → run the pipeline on a real sample, check row counts, dtypes, nulls,
     and a spot-check of values — not just "it ran".
   - **Tests** → run them, but tests alone are not verification of a runtime change.
3. **Grade against the contract.** Walk each acceptance criterion in
   `.loops/contract.md`. Pass/fail with observed evidence.
4. **On any failure, fix and rerun from step 1.** Never hand back partially
   verified work. Append the result to `.loops/log.md`.

## Bootstrapping a project verify skill

If a repo has a natural "run it" flow, encode it once as a project-local skill so
future loops self-verify automatically. Prefer quantitative checks — a number is
easier to verify against than a vibe.

## Escalate to a second agent

For anything non-trivial, hand the diff to the **`evaluator`** agent (fresh,
adversarial context) or run native **`/code-review`**. The builder verifying its
own work is the failure mode this loop guards against.

## Do not

- Declare done from "the code looks right."
- Skip verification because a change "looks like a one-liner."
- Verify only the happy path — exercise the failure and edge cases too.
