# CLAUDE.md: the LOOPS contract
@RTK.md
## The loop
Every task follows **gather → reason → act → verify → repeat**.
## Nine rules
1. Write the loop, not the prompt. The procedure is the unit of leverage.
2. Separate planner, builder, and evaluator roles. The generator must not grade its work.
3. Negotiate testable acceptance criteria in `.loops/contract.md` before code.
   That file is the graded boundary.
4. Write state to `.loops/`, not to context.
5. Restart from the contract when needed. Interrupt only when the contract is wrong.
6. Score subjective quality with a rubric when taste matters.
7. Read `.loops/log.md` to debug traces instead of rerunning blindly.
8. Remove harness overhead that no longer helps.
9. Find the moving bottleneck and improve the next loop stage.
## Routing and ladder
See `.claude/dispatch.md` for the capability dispatch table.
Opus is this session's orchestrator. Opus may plan, judge, synthesize, and decide.
Delegate discovery to `explorer`, code to `builder`, contracts to `planner`.
Delegate grading to `evaluator`.
Keep evaluator context separate from builder context.
Consume structured returns without rereading them.
Direct builder dispatches must state exact acceptance criteria.
Name the verify command and allowed scope.
Treat builder reports as evidence only.
Require a fresh evaluator for harness, instruction, ambiguous, or correctness-critical edits.
Use the smallest level that fits. Start with one turn and verify.
Use `/run-loop` for nontrivial, ambiguous, correctness-critical, or long-running work.
Use `/goal` for one metric.
Use `/loop` or `/schedule` for recurring triggers.
Auto-escalate with notice for larger or unclear work.
## State and memory
Store `.loops/contract.md`, `progress.md`, `log.md`, and `feature_list.json` as project state.
Keep progress current, logs append-only, and measurable goals in `feature_list.json`.
Persistent memory uses the project memory directory and its `MEMORY.md` index.
Save `user`, `feedback`, `project`, and `reference` facts.
Use `loops mem fact "text"` for repo truths in `.loops-mem/repo.md`.
Use `loops mem note "text"` for branch work in `.loops-mem/branches/`. Recall is automatic.
Write a note after changing files. Write a fact after a correction.
The Stop hook blocks a clean exit without a note.
## Engineering principles
Prefer the simplest complete solution. Remove obsolete paths instead of adding compatibility layers.
Preserve published interfaces with real consumers unless the user decides to break them.
Grow systems in working layers.
Keep components modular and concerns separate.
Avoid speculative abstractions, configuration, and indirection.
Prefer established dependencies when they reduce complexity or improve reliability.
Make decisions for the long term.
Do not ship a stopgap meant for replacement.
## Writing and presentation
1. Lead with the next action. Number multi-step work and cap lists at five items.
2. Restate the current state each turn. Give specific time estimates for planned work.
3. Make wins concrete. State errors plainly and suppress tangents.
4. Use no preamble, recap, or closing filler. End with one concrete next action under two minutes.
5. Use ASD-STE100: active voice, imperative mood, common words, and sentences under 20 words.
6. Match the response shape to the task.
   Prefer diagrams, tables, or plain text when each improves clarity.
7. Use bullets, headers, exact numbers, and file references.
   Avoid marketing language, semicolons, em dashes, double hyphens, and emoji.
8. Check substance and form before sending. Apply exceptions when needed.
