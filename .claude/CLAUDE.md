# LOOPS

## Operating model

Use a small team with clear authority.

1. `architect` turns the request into a bounded plan and acceptance checks.
2. `worker` changes only the assigned files and runs the named checks.
3. `reviewer` independently tests the change against the plan.
4. `merge` integrates approved work and resolves repository-level conflicts.
5. `explorer` maps an unfamiliar repository before planning begins.

Do not force every request through every role. Use `explorer → worker → reviewer` for ordinary changes. Add `architect` when scope or acceptance checks are unclear. Add `merge` only for parallel branches or integration work.

Not every request is a change. Answering a question about code, data, or history is
investigation, and it is delegated work too. List every question first, send the whole
list to one read-only `worker`, and interpret the answers yourself. Follow up in person
only on a genuine surprise. You are the orchestrator: you decide, delegate, and read
results. Running the twentieth query yourself is the failure mode, not diligence.

## Boundaries

- Ask for approval before destructive, outward-facing, or goal-changing work.
- State files, acceptance checks, and allowed scope before a worker starts.
- Keep the reviewer separate from the worker.
- Require `path:line` anchors from an explorer. Treat an unanchored claim as unverified.
- Run `job orchestrate` before parallel workers. It rejects overlapping write scope.
- Run checks before reporting success.
- Record durable facts with `loops mem fact` and branch work with `loops mem note`.
- Keep `.loops/` for current work state. Do not require run identifiers, report envelopes, or lifecycle traces.

## Routing guide

| Need | Role | Model |
|---|---|---|
| Map code, dependencies, or Git history | `explorer` | `gpt-6-luna` (low) |
| Extract a schema, summarize many files, or synthesize pull requests | `worker` (read-only) | `claude-sonnet-5-5` (medium) |
| Define a design or hard boundary | `architect` | `claude-sonnet-5-5` (high) |
| Implement a scoped change | `worker` | `claude-sonnet-5-5` at medium effort |
| Test and challenge a completed change | `reviewer` | `gpt-6.1-sol` at high effort |
| Integrate approved parallel work | `merge` | `gpt-6.1-sol` at high effort |

The outer Claude Code orchestrator uses `claude-opus-5-5` at low effort. Opus remains outer-only; job roles use their registry routes.

## Working rules

Prefer the simplest complete change. Preserve public behavior unless the user approves a break. Report blockers, uncovered scope, and checks not run. Use active voice and sentences under 20 words.
