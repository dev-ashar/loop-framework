---
name: job-framework
description: Internal orchestration bridge for natural-language goals and validated builder DAGs.
---

# Job framework

Use this skill internally after the user gives a natural-language goal.
Never ask the user to run an internal `loops job` command.

## Route

1. Read explorer evidence and the approved `.loops/contract.md` only.
2. Keep one legacy builder when one useful implementation step exists.
3. Build a DAG when at least two useful builder steps exist.
4. Write `.loops/runs/<runId>/job-dag.json` with `job_contract_bridge`.
5. Validate the DAG before ledger, branch, worktree, context, or dispatch creation.
6. Construct one canonical context file per job.
7. Dispatch through the existing adapter and runtime.

The bridge rejects empty steps, non-builder roles, unknown or overlapping scopes, missing verification, cycles, stale contract hashes, unknown profiles, tiers, and lenses.
It is deterministic and never invents scopes.

## Canonical context

The adapter receives one JSON file owned by the run. It contains exactly:

`jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId contractHash baseSha repositoryRoot worktreePath`

The runtime deletes the file after consumption. Validate repository root, active contract hash, model mapping, base SHA, worktree, and scope before process creation.
Return `JOB_CONTEXT_INVALID field=<field>` without a process marker on failure.

The adapter treats `verify`, `writeScope`, and `lenses` as authoritative. It cannot change model, scope, dependencies, or verification.
Resolve profile, tier, and model from `templates/job-profiles.json`.
Dispatch through the existing Agent or process boundary only after approval observation.

## Gates and failures

Use this order: approval, envelope, builder report, verification, scope, evaluator, accounting, integration.
Validate the envelope before parsing any report.
Use bounded escalation and retries from the selected profile.
Unavailable models, gateway authentication, missing approval, malformed context, stale hashes, invalid DAGs, and adapter failures return `BLOCKED` before builder creation.
Test adapters are construction-time fixtures only.
Do not select them from files, stdin, environment, user text, or runtime arguments in production.
Integrate only evaluated, scope-valid jobs.
Stop on conflicts and preserve source branches.
Stop for exact contract approval, outward actions, destructive actions, or original-goal changes.

`run-loop` uses this skill only after contract approval when at least two useful builder jobs exist. No-DAG and one-job goals use the legacy route.
