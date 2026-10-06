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
| `explorer` | `gpt-6-luna` (low) | Map code, tests, dependencies, and read-only Git history. |
| `architect` | `claude-sonnet-5-5` (high) | Define scope and choose acceptance checks. Never implement. |
| `worker` | `claude-sonnet-5-5` (medium) | Implement one scoped assignment. |
| `reviewer` | `gpt-6.1-sol` (high) | Independently test and challenge completed work. |
| `planner` | `claude-sonnet-5-5` (high) | Conditional planning capability when boundaries remain unclear. |
| `merge` | `gpt-6.1-sol` (high) | Integrate approved parallel branches. |

All AI routes use HAIP. Candidate models remain unroutable. Role models are chosen with `loops models set`. OMP remains optional and experimental.

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
`loops models set <role>` fetches the live HAIP model list, prints a numbered menu (current model marked), and applies your choice from stdin.
`loops models set <role> <model> [--force] [--effort <level>]` validates the id against the live list (`--force` skips this when HAIP is unreachable).
Applying a model registers it if missing, repoints the role's profile, and updates the agent frontmatter. Effort is kept unless `--effort` is given. A model left with no roles is pruned from the registry.
Every model has a 1000000-token context window unless `lib/session.sh` holds an explicit entry.
`loops session set <model>` changes the session model and its context window for this repository.
Add `--user` to change the global default in `~/.claude/settings.json`.

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

# Offline evaluation fixtures are validated locally; no paid or network evaluation runs.
