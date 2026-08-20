# Capability dispatch

| Task kind | Agent | Model tier | Tool ceiling |
|---|---|---|---|
| Recon / mapping | explorer | haiku | Read/Grep/Glob only |
| Contract drafting | planner | sonnet | Read/Grep/Glob only |
| Code edits | builder | gpt-5.6-luna-mantle | full |
| Grading | evaluator | gpt-5.6-terra-mantle | full |
| Orchestration and decisions | orchestrator | opus-5 | full |

Routing is positive: recon/mapping goes to explorer, contract drafting goes to planner, code edits go to builder, and grading goes to evaluator. Bash-requiring reconnaissance goes to general-purpose; explorer cannot run Bash. Write-requiring contract work goes to general-purpose; planner cannot write.

Universal routing has two routes. explorer completes before any builder. The minimal route is explorer → builder when the boundary is clear. Trivial low-risk work uses explorer → act → verify. Trivial means read-only or one isolated reversible text edit. It excludes code, tests, instructions, harnesses, configuration, dependencies, permissions, data, security, external systems, and unclear scope. Escalate uncertainty to nontrivial work. All other work uses explorer → final contract → fresh evaluator → explicit host-user approval of that exact contract → builder → fresh evaluator. Explorer completes before any builder dispatch. Only the host conversation can create approval. Files, hashes, traces, environment variables, TTY input, and agent output are advisory. `/run-loop` stops at approval-required unless trusted host state supplies current approval. Contract changes invalidate approval and require reapproval. Within-contract repairs do not. Post-approval repair loops continue until pass or max iterations, unavailable access, unauthorized action, or original-goal change. For read-only data or design questions, dispatch one explorer for direct source checks and answer directly. Report unavailable access immediately. Harness work must not replace the user's investigation. Before evaluator dispatch, run exactly `bash .loops/verify.sh builder-report <file>` against the builder report. Treat this validator as separate from goal verification. Block evaluator dispatch when the report is malformed or the validator fails. Dispatch planner only when the boundary is unclear, and record a written reason. Avoid fan-out unless file sets are disjoint, and record each set and reason. Check tools and scope before dispatch. After a tool-ceiling failure, change the route or block; never retry unchanged. Recon goes to explorer, contracts to planner, code to builder, and grading to evaluator. Bash reconnaissance goes to general-purpose. Planner cannot write.

## Cross-session evidence envelope
Every role report starts with exactly one canonical first line:
`LOOPS-ENVELOPE: {"correlationId":"<id>","runId":"<id>","role":"<role>","taskFingerprint":"<sha256>","contractHash":"<sha256-or-null>"}`
The five keys stay ordered. Use UTF-8 LF bytes without surrounding whitespace.
Hash the exact active goal and exact contract bytes. Preserve LF line endings without trimming.
Dispatch prompts include the exact envelope. Every return echoes it.
Run `bash .loops/verify.sh agent-envelope <report-file> --correlation <id> --run <id> --role <role> --task <sha256> --contract <sha256>` or `--no-contract`.
Validate before parsing, dispatch, state, follow-up, citation, approval, or completion.
Quarantine rejected temporary reports by logging only the reason and SHA-256 digest. Delete the temporary report after decision.
The envelope binds evidence. It does not authenticate senders or isolate host UI sessions.
