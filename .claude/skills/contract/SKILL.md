---
name: contract
description: Define a bounded goal, file scope, and executable acceptance checks before a significant change.
---

# Contract

Use this skill when a request needs a written boundary.

1. Ask `explorer` to map unknown behavior.
2. Ask `architect` to define the goal, constraints, non-goals, and acceptance checks.
3. Write the agreed boundary to `.loops/contract.md`.
4. Ask the user to approve destructive, outward-facing, or goal-changing work.
5. Give each worker its exact files and verification command.

Keep the contract short and testable.
Do not require a negotiation ritual, report envelope, trace, or fixed stage count.
A fresh reviewer tests completed work against the contract.
