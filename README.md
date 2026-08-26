# LOOPS

LOOPS installs a focused Claude Code team for repository work.
It keeps role separation without a fixed conveyor or mandatory run bureaucracy.

## Install

Prerequisites: Git, Bash, jq, Python 3, and Claude Code.

```bash
git clone <repository>
cd loops
bash install.sh
```

Preview installation without changes:

```bash
bash install.sh --dry-run
```

The installer backs up managed Claude files under `~/.claude/backups/`.
It preserves unrelated settings, plugins, hooks, marketplaces, permissions, and lessons.
It links this clone into `~/.claude`, so keep the clone in place.
Reinstall after moving the clone to repair links.

## Team

| Role | Model | Use |
|---|---|---|
| `explorer` | `gemini-3.1-flash-lite` | Map code, tests, dependencies, and read-only Git history. |
| `architect` | `claude-opus-5` | Define design, scope, non-goals, and acceptance checks. |
| `worker` | `gpt-5.6-luna-mantle` | Implement one scoped assignment. |
| `reviewer` | `gpt-5.6-terra-mantle` | Independently test and challenge completed work. |
| `merge` | `gpt-5.6-terra-mantle` | Integrate approved parallel branches. |

## Routing guide

Choose the smallest route that fits the request.

| Situation | Route |
|---|---|
| Known one-file change | `worker → reviewer` |
| Unfamiliar repository | `explorer → worker → reviewer` |
| Unclear scope or interface | `explorer → architect → worker → reviewer` |
| Parallel approved work | `explorer → architect → workers → reviewers → merge` |

The worker never reviews its own result.
The reviewer runs checks before approval.
The merge role stops on conflicts.

## Daily use

Ask Claude naturally for the change you need.
For a longer task, use:

```text
/run-loop "make the ingestion pipeline idempotent"
```

Claude maps unfamiliar code, plans only when needed, implements scoped work, and reviews it independently.
It asks before destructive actions, outward actions, or goal changes.

## Configuration

`loops models list` shows the configured role roster.
`loops models set <role> <model>` changes a role model.
`loops session set <model>` changes the session model and its context window.

The role definitions live in `.claude/agents/`.
The job profiles live in `templates/job-profiles.json`.
The job DAG schema lives in `templates/job-dag.schema.json`.

## State and recovery

Current work state lives in `.loops/`.
Durable repository facts live in `.loops-mem/`.
Use `loops mem note` for branch work and `loops mem fact` for repository facts.

If an installed link is missing, run `bash install.sh` from this clone.
If a model is unavailable, select an available model and retry.
If a hook fails, inspect its output and restore the latest backup before reinstalling.

Restore a managed path by copying it from `~/.claude/backups/pre-loops-*` into `~/.claude`.
