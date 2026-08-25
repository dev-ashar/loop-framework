# Contract — install once, speak naturally

This contract adds the user-facing installation and agent workflow for the completed job framework.
The existing DAG runtime remains the implementation base and must not regress.

## Goal

A user clones LOOPS once, runs `bash install.sh` once, then asks Claude naturally for work.
The orchestrator creates, validates, executes, evaluates, and integrates job DAGs internally.
The user never needs to invoke `loops job` commands.

## Constraints

- Preserve the completed job runtime and its approved legacy baseline.
- Test installer effects only in copied repositories and isolated temporary homes.
- Keep internal CLI details away from the normal user workflow.
- Require exact host approval before any builder execution.
- Use existing agent roles, profiles, schemas, worktrees, evaluators, and integration gates.
- Do not add external services, package managers, or a second state store.

## User interface

The supported user journey is:

```text
git clone <repository>
cd loops
bash install.sh
```

After installation, the user speaks naturally in Claude Code or invokes:

```text
/run-loop "<goal>"
```

`loops job ...` remains an internal agent and harness interface. README usage must not
present it as a user workflow. The installed `loops` executable is not required to accept
free-form natural-language goals.

## Installation behavior

- `bash install.sh --dry-run` prints planned backup, settings merge, agent, skill, hook,
  and CLI-link actions without creating or changing any path.
- `bash install.sh` works against an isolated `HOME` and does not write outside that home
  except reading the cloned repository.
- Installation backs up every managed pre-existing path before replacement.
- Installation preserves unrelated plugins, marketplaces, permissions, hooks, and settings.
- Installation preserves existing lesson JSONL bytes.
- Repeated installation creates no duplicate settings entries and retains correct links.
- A failed settings merge or missing required source fails before replacing managed paths,
  or restores the captured backup before returning nonzero.
- Installed links resolve to the clone. Documentation states that moving or deleting the
  clone breaks those links and that reinstalling repairs them.
- The installer installs the `job-framework` skill with all existing agents and skills.

## Agent-facing skill

Add `.claude/skills/job-framework/SKILL.md` as an internal orchestrator skill.
It must instruct the orchestrator to:

1. Accept the user's natural-language goal from the active conversation.
2. Use explorer evidence and the approved contract as the only planning boundary.
3. Generate builder jobs only when at least two implementation steps are useful.
4. Preserve the legacy single-builder route when one job is sufficient.
5. Write an ignored per-run DAG under `.loops/runs/<runId>/job-dag.json`.
6. Validate the DAG before runtime state, branch, worktree, or dispatch creation.
7. Construct one canonical context object per job.
8. Dispatch through the existing adapter and job runtime.
9. Validate builder and evaluator envelopes and report grammar before consumption.
10. Integrate only evaluated, scope-valid jobs and stop on conflict.
11. Never ask the user to run an internal job CLI command.
12. Stop for exact contract approval, outward actions, destructive actions, or original-goal changes.

Extend `run-loop` so that after contract approval it uses this skill when the approved
plan contains at least two useful builder jobs. No-DAG and one-job work stays on the
legacy path without extra ceremony.

## Contract-to-DAG bridge

Add one internal bridge that consumes:

- the active approved contract path and full SHA-256
- a planner-provided list of builder steps
- exact file scopes, dependencies, verification commands, profiles, tiers, and lenses

It emits schema-version-1 JSON accepted by `templates/job-dag.schema.json` and
`templates/job-profiles.json`. It rejects empty steps, non-builder roles, unknown files,
missing verification, overlapping scopes, cycles, stale contract hashes, unknown profiles,
unknown tiers, and unknown lenses before runtime state or dispatch.

The bridge is deterministic for identical canonical input. It does not invent source-file
scopes. Missing exact scopes returns `BLOCKED` for planner correction.

## Canonical job context

Every builder adapter receives one JSON object containing exactly:

```text
jobId role profile modelTier modelId dependsOn writeScope verify lenses
runId dispatchId contractHash baseSha repositoryRoot worktreePath
```

The context is derived from the validated DAG and active runtime. The adapter receives the
context through one file descriptor or one temporary file owned by the run, not through
independent free-form environment overrides. The runtime deletes it after consumption.

Before process creation, validate required keys, exact repository root, active contract
hash, model mapping, base SHA, worktree path, and declared scope. Missing or mismatched
context returns `JOB_CONTEXT_INVALID field=<field>` with no process marker.

The builder definition documents how to read this context and that its `verify`, scope,
and lenses are authoritative. The builder cannot change its model, scope, dependencies,
or verification command.

## Adapter and failure behavior

Document the internal adapter in the job-framework skill and `.claude/dispatch.md`:

- context input and lifecycle
- profile-to-tier-to-model resolution
- process or Agent-tool dispatch boundary
- approval observation before builder creation
- envelope and report validation order
- verification and scope-check timing
- evaluator lens composition
- escalation and retry bounds
- integration and conflict behavior

Unavailable models, failed gateway authentication, missing approval observation, malformed
context, stale hashes, invalid DAGs, and adapter failures return bounded `BLOCKED` results
before builder creation. Test adapters are construction-time fixtures and cannot be
selected by files, stdin, environment, user text, or runtime arguments in production.

## Documentation

Update README with:

- prerequisites
- clone and one-command installation
- dry-run and reinstall behavior
- natural-language and `/run-loop` examples
- the approval pause
- what agents do automatically
- where state and backups live
- how to uninstall or restore from backup
- the clone-must-remain limitation
- troubleshooting for missing links, unavailable models, and hook errors

Keep internal `loops job` commands in a maintainer reference, separate from user usage.

## Acceptance criteria

1. Dry-run against an empty temporary HOME exits zero, lists all managed actions, and leaves the complete filesystem digest unchanged.
2. Fresh installation in a copied repository and isolated HOME creates working links for CLAUDE.md, agents, skills including job-framework, hooks, and `~/.local/bin/loops`.
3. Installation writes nothing outside the isolated HOME and copied repository fixture.
4. Seeded unrelated settings, plugins, permissions, marketplaces, and hooks survive semantically unchanged.
5. Existing lesson bytes survive first and repeated installation unchanged.
6. A second installation creates no duplicate hooks or settings and leaves managed link targets unchanged.
7. A forced malformed-settings and missing-source fixture exits nonzero without partial replacement and proves backup restoration.
8. The job-framework skill routes a fixture natural goal to a two-job DAG without asking for internal CLI use.
9. A one-step fixture uses the legacy single-builder route and creates no DAG scratch.
10. The bridge produces deterministic valid JSON with exact scopes, dependencies, verify commands, profiles, tiers, lenses, and active contract hash binding.
11. Invalid or stale bridge inputs produce no ledger, branch, worktree, context, or dispatch marker.
12. Every builder fixture receives the exact canonical job-context keys and values from the validated DAG and active runtime.
13. Missing or mismatched context fields block before process creation with the exact diagnostic.
14. The observed adapter model ID equals the profile mapping and cannot be overridden by environment or user text.
15. Approval, envelope, builder-report, verification, scope, evaluator, accounting, and integration gates execute in that order.
16. A dependency fixture runs the successor only after the predecessor reaches `integrated`.
17. A conflict fixture stops integration, preserves source branches, and leaves the main worktree clean.
18. README user commands execute successfully in the isolated fixture and no user-usage block requires `loops job`.
19. Existing six job suites still emit their exact success tokens.
20. The legacy suite remains exactly 35/37 with only approved failures 14 and 21.
21. Contract negotiation, explorer, full verification, shell syntax, and diff hygiene pass.

## Behavioral test

Create `tests/agent-experience.sh`. It must copy the repository to a temporary fixture,
use an isolated HOME, and test the complete install and agent-adapter journey. It must
exercise real installer writes, links, settings merges, rollback, DAG generation, context
construction, adapter argv, runtime order, dependency execution, and failure cases.
Documentation-only grep checks cannot satisfy behavioral criteria.

The final line on success is exactly:

```text
AGENT_EXPERIENCE_OK
```

## Task allowlist

- `install.sh`
- `README.md`
- `run.sh`
- `lib/job-*.sh`
- `.claude/dispatch.md`
- `.claude/agents/builder.md`
- `.claude/skills/job-framework/SKILL.md`
- `.claude/skills/run-loop/SKILL.md`
- `tests/agent-experience.sh`
- existing `tests/job-*.sh` only for integration
- `.loops/verify.sh`
- `.loops/contract.md`
- `.loops/progress.md`
- `.loops/feature_list.json`
- `.loops/log.md` append-only

Do not modify hooks, settings source files, external services, or unrelated files.

## Verify

Run independently:

```bash
bash tests/agent-experience.sh
bash tests/job-framework.sh
bash tests/job-executor.sh
bash tests/job-dispatch.sh
bash tests/job-integration.sh
bash tests/job-lifecycle.sh
bash tests/job-runtime.sh
bash tests/run_tests.sh
bash tests/contract-negotiation.sh
bash tests/explorer-git-gh.sh
bash .loops/verify.sh
bash -n install.sh run.sh lib/job-*.sh tests/agent-experience.sh
git diff --check
```

`tests/agent-experience.sh` must exit zero and end with `AGENT_EXPERIENCE_OK`.
The legacy suite may exit nonzero only with the exact approved 35/37 baseline.
