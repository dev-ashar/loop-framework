# Capability dispatch

Use the smallest team that can complete the work.

| Task | Role | Model | Tools |
|---|---|---|---|
| Repository mapping and read-only research | `explorer` | `gpt-6-luna` (low) | Read, Grep, Glob, Bash |
| Design, contracts, and plan review | `architect` | `claude-sonnet-5-5` (high) | Read, Grep, Glob, Bash |
| Scoped implementation | `worker` | `claude-sonnet-5-5` (medium) | full |
| Independent verification | `reviewer` | `gpt-6.1-sol` (high) | full |
| Branch integration and conflicts | `merge` | `gpt-6.1-sol` (high) | full |

## Route selection

1. Use `explorer` before changing an unfamiliar repository.
2. Keep `explorer` on locating and mapping. Route full schema extraction,
   multi-file summary, and cross-pull-request synthesis to a read-only `worker`.
3. Treat investigation as delegated work, not orchestrator work. List every question
   first, send the whole list to one read-only `worker`, and read only the answers.
   Follow up yourself only on a genuine surprise. This covers data, logs, and history,
   not just source code.
4. Use `architect` when requirements, scope, or acceptance checks are unclear.
5. Give each `worker` exact files, acceptance checks, and one verify command.
6. Dispatch a fresh `reviewer` after correctness-critical or multi-file work.
7. Use `merge` only after workers and reviewers approve parallel branches.
8. Before dispatching two or more workers at once, write the assignments and run
   `bash run.sh job orchestrate "<goal>" <assignments.json>`. It rejects overlapping
   `writeScope` before any worker starts. One worker needs no DAG.

The common route is `explorer → worker → reviewer`.
The direct route is `worker → reviewer` when the repository and scope are already clear.
The design route is `explorer → architect → worker → reviewer`.
The parallel route adds `merge` after each branch passes review.

## Role boundaries

- `explorer` performs bounded, read-only research. It may run read-only Git and GitHub commands.
- `architect` defines boundaries. It does not implement the plan it approves.
- `worker` implements one scoped assignment. It does not review its own work.
- `reviewer` runs the stated checks and tries to find failures. It does not fix the work.
- `merge` integrates only reviewer-approved branches. It stops on conflicts.

## Job configuration

Job profiles map each role to supported capabilities and model tiers.
The DAG schema accepts the five named roles and explicit dependencies.
Workers require an exact `writeScope` and `verify` command.
Reviewers require one or more evaluation lenses.

Do not require fixed stages, envelopes, traces, correlation identifiers, or report validators.
Use plain reports with changed files, commands, results, and blockers.

## Model routing

Workers run on `claude-sonnet-5-5` at medium effort. The outer Claude Code
orchestrator uses `claude-opus-5-5` at low effort and never implements.

Architecture and planning use `claude-sonnet-5-5` at high effort. Opus 5.5 remains the low-effort outer orchestrator and never appears in job roles.
Reviewers and merge use `gpt-6.1-sol` at high effort. Change a role model with `loops models set <role>` (interactive numbered menu from the live HAIP list)
or `loops models set <role> <model-id> [--force] [--effort <level>]`. The registry holds only models
that a role uses; a model is pruned when its last role moves away. Context window defaults to 1000000.
