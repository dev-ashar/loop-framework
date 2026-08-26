# Capability dispatch

Use the smallest team that can complete the work.

| Task | Role | Model | Tools |
|---|---|---|---|
| Repository mapping and read-only research | `explorer` | `gemini-3.1-flash-lite` | Read, Grep, Glob, Bash |
| Design, contracts, and plan review | `architect` | `claude-opus-5` | Read, Grep, Glob, Bash |
| Scoped implementation | `worker` | `gpt-5.6-luna-mantle` | full |
| Independent verification | `reviewer` | `gpt-5.6-terra-mantle` | full |
| Branch integration and conflicts | `merge` | `gpt-5.6-terra-mantle` | full |

## Route selection

1. Use `explorer` before changing an unfamiliar repository.
2. Use `architect` when requirements, scope, or acceptance checks are unclear.
3. Give each `worker` exact files, acceptance checks, and one verify command.
4. Dispatch a fresh `reviewer` after correctness-critical or multi-file work.
5. Use `merge` only after workers and reviewers approve parallel branches.

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

Workers run on `gpt-5.6-luna-mantle` by default and `gemini-3.7-flash` for the fast
parallel tier. Never route an implementation leaf to `claude-opus-5` or
`gpt-5.6-sol-mantle`. Opus is an architect-only model, not a worker escalation target.

The main/default orchestrator remains `claude-opus-5`.
Architecture uses `claude-opus-5`. When Opus is genuinely uncertain about one major
decision, dispatch one `gpt-5.6-sol-mantle` architect for a second opinion. Opus makes
the final decision and continues. Sol is never the default orchestrator, worker,
reviewer, or merge model.

Reviewers run on `gpt-5.6-terra-mantle` by default. Use `gemini-3.1-pro` as the secondary review route.
