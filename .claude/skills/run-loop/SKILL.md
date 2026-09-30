---
name: run-loop
description: Run a bounded multi-role change from mapping through independent review.
argument-hint: "<goal>"
---

# Run loop

Use this skill for a nontrivial repository change.

1. Dispatch `explorer` when repository behavior is not already known.
2. Dispatch `architect` when scope, interfaces, or acceptance checks are unclear.
3. Ask the user for approval before destructive, outward-facing, or goal-changing work.
4. Dispatch `worker` with exact files and a verification command, plus the objective and constraints. Workers use Luna at max effort.
5. After substantive worker changes, dispatch a fresh read-only `reviewer` to run the checks and challenge the result.
6. Dispatch `merge` only for independently reviewed parallel branches.

Use the smallest route that fits.
Do not require a fixed sequence, report envelope, trace record, or internal job command.
Stop when the reviewer approves, the user declines, or a blocker needs a decision.
