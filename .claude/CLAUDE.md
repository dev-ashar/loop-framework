# LOOPS

## Operating model

Use a small team with clear authority.

1. `architect` turns the request into a bounded plan and acceptance checks.
2. `worker` changes only the assigned files and runs the named checks.
3. `reviewer` independently tests the change against the plan.
4. `merge` integrates approved work and resolves repository-level conflicts.
5. `explorer` maps an unfamiliar repository before planning begins.

Do not force every request through every role. Use `explorer → worker → reviewer` for ordinary changes. Add `architect` when scope or acceptance checks are unclear. Add `merge` only for parallel branches or integration work.

## Boundaries

- Ask for approval before destructive, outward-facing, or goal-changing work.
- State files, acceptance checks, and allowed scope before a worker starts.
- Keep the reviewer separate from the worker.
- Run checks before reporting success.
- Record durable facts with `loops mem fact` and branch work with `loops mem note`.
- Keep `.loops/` for current work state. Do not require run identifiers, report envelopes, or lifecycle traces.

## Routing guide

| Need | Role | Model |
|---|---|---|
| Map code, dependencies, or Git history | `explorer` | `gemini-3.1-flash-lite` |
| Define a design or hard boundary | `architect` | `claude-opus-5`; one `gpt-5.6-sol-mantle` second opinion only when Opus is genuinely uncertain |
| Implement a scoped change | `worker` | `gpt-5.6-luna-mantle` |
| Test and challenge a completed change | `reviewer` | `gpt-5.6-terra-mantle` |
| Integrate approved parallel work | `merge` | `gpt-5.6-terra-mantle` |

## Working rules

Prefer the simplest complete change. Preserve public behavior unless the user approves a break. Report blockers, uncovered scope, and checks not run. Use active voice and sentences under 20 words.
