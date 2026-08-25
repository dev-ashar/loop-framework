# Capability dispatch

| Task kind | Agent | Model tier | Tool ceiling |
|---|---|---|---|
| Recon / mapping | explorer | haiku | Read/Grep/Glob/Bash |
| Contract drafting | planner | sonnet | Read/Grep/Glob only |
| Code edits | builder | gpt-5.6-luna-mantle | full |
| Grading | evaluator | gpt-5.6-terra-mantle | full |
| Orchestration and decisions | orchestrator | opus-5 | full |

## Explorer Git and GitHub route

Route read-only local Git research and authenticated GitHub queries to `explorer`.
Before dispatch, inspect `.claude/agents/explorer.md` and require direct `Bash`.
Run `git --version`, `gh --version`, and `git rev-parse --show-toplevel`.
Run `gh auth status` before authenticated GitHub queries.
Record each command and exit status in the dispatch evidence.

Return `BLOCKED` for a missing binary, failed repository check, missing Bash capability, or failed authentication.
Reroute only to another equivalent capable read-only route with valid authentication.
Never use full-Bash `general-purpose` as a degraded fallback.
Never report partial, guessed, unauthenticated, or degraded research as complete.

## Internal job adapter

The adapter accepts one run-owned canonical context file. It resolves profile, tier, and model from `templates/job-profiles.json`, observes approval before builder creation, and validates envelope and builder report before verification, scope, evaluator, accounting, and integration gates. The context keys are `jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId contractHash baseSha repositoryRoot worktreePath`. The adapter rejects unavailable models, failed gateway authentication, missing approval, stale hashes, invalid DAGs, malformed context, and adapter failures before process creation. Escalation follows profile bounds. Integration stops on conflict.

Record every dispatch with this schema.

```
EXPLORER_PREFLIGHT:
  route: explorer
  command: <exact command>
  exit: <decimal status>
  status: COMPLETE|BLOCKED|REROUTE
  detail: <bounded reason or result>
```

Use one block for every command, in execution order.
Set `COMPLETE` only after all required preflight and research commands succeed.
Set `REROUTE` only after recording the selected equivalent route.
Set `BLOCKED` when no equivalent route exists or authentication fails.
If dispatch is unavailable, record `EXPLORER_DISPATCH: unavailable reason=<bounded reason>` and `BLOCKED`.
Do not emit completion for blocked or rerouted research without the selected route.

Hooks cannot identify agent roles reliably.
Hooks cannot guarantee that every arbitrary shell mutation is impossible.

Universal routing remains positive: explorer completes before any builder. The minimal route is explorer → builder when the boundary is clear. All other work uses explorer → final contract → fresh evaluator → explicit host-user approval → builder → fresh evaluator. Approval requests must show the contract path, exact review command, active hash, and bounded bullets. Before evaluator dispatch, run exactly `bash .loops/verify.sh builder-report <file>` against the builder report. Treat this validator separately from goal verification. Dispatch planner only when the boundary is unclear, and record a written reason. Avoid fan-out unless file sets are disjoint. After a tool-ceiling failure, change the route or block; never retry unchanged.

## Cross-session evidence envelope

Every role report starts with exactly one canonical first line:
`LOOPS-ENVELOPE: {"correlationId":"<id>","runId":"<id>","role":"<role>","repoRoot":"<absolute-canonical-root>","taskFingerprint":"<sha256>","contractHash":"<sha256-or-null>"}`
The six keys stay ordered. Use UTF-8 LF bytes without surrounding whitespace.
Hash the exact active goal and exact contract bytes. Preserve LF line endings without trimming.
Dispatch prompts include the exact envelope. Every return echoes it.
Run `bash .loops/verify.sh agent-envelope <report-file> --correlation <id> --run <id> --role <role> --task <sha256> --contract <sha256>` or `--no-contract`.
Validate before parsing, dispatch, state, follow-up, citation, approval, or completion.
Quarantine rejected temporary reports by logging only the reason and SHA-256 digest. Delete the temporary report after decision.
The envelope binds evidence. It does not authenticate senders or isolate host UI sessions.
