# Contract — authorized harness repair

Locked for the active repair run. The evaluator grades only this contract.

## Goal

Repair the LOOPS dispatch, contract, reporting, and verification protocol identified by the planner's RCA.

## Constraints

- Always use subagents for task work. The orchestrator must not perform explorer or builder work inline.
- Always explore before building. The universal minimal route is `explorer → builder`.
- Add `planner` only when the boundary is unclear. Record a written reason before that call.
- Add a fresh `evaluator` for harness, instruction, ambiguous, or correctness-critical work.
- Avoid fan-out unless work is truly disjoint. Record a written reason for every additional call.
- Reroute when an agent lacks a required tool or capability. Do not retry an unchanged call after a tool-ceiling failure.
- Before planning or expanding theory for a production-data incident, dispatch an explorer to run the cheapest decisive read-only evidence check when access exists. For object-freshness incidents, enumerate candidate relations and compare latest timestamps and state first. Reject plan-only returns when executable evidence was requested. Any retry must change the method or route. Urgency reduces ceremony and uses the minimal explorer-only investigation when no build is needed; building still requires subagents and explorer-before-builder.
- Harness work must never become the moving bottleneck or replace the user's actual investigation. For read-only data or design questions, dispatch one explorer for direct source checks and answer directly. Do not invoke `/run-loop`, contract negotiation, builder, or evaluator unless code changes are requested or a correctness-critical artifact must be graded. Report unavailable required access immediately. Cap harness repair at one attempt, then return to the original goal. Reject cycles where no source query ran and only `.loops/` changed.
- Keep authoritative contract and run-state persistence under orchestrator control. Read-only planners return proposals; they do not write authoritative state.
- Treat builder output as evidence. The fresh evaluator remains the only grading authority.
- The approved implementation files are exactly: `.claude/CLAUDE.md`, `.claude/dispatch.md`, `.claude/agents/planner.md`, `.claude/agents/builder.md`, `.claude/agents/explorer.md`, `.claude/agents/evaluator.md`, `.claude/skills/contract/SKILL.md`, `.claude/skills/run-loop/SKILL.md`, `run.sh`, `.loops/verify.sh`, `tests/run_tests.sh`, optional new `tests/contract-negotiation.sh`, and evidence files under `.loops/evidence/`. `.claude/agents/explorer.md` and `.claude/agents/evaluator.md` implement the canonical task envelope, quarantine boundary, default-path checks, refutation scope, and SQL negative-space rules.
- The pre-existing modified-path baseline is exactly: `.claude/CLAUDE.md`, `.claude/agents/evaluator.md`, `.claude/dispatch.md`, `.claude/skills/contract/SKILL.md`, `.claude/skills/run-loop/SKILL.md`, `.loops/log.md`, `.loops/verify.sh`, `README.md`.
- `.loops/evidence/preexisting.patch` is the immutable `git diff --binary` evidence for exactly those eight baseline paths, captured before repair implementation.
- Unchanged protected files remain byte-identical to materialized baseline.
- `.claude/agents/evaluator.md` is an approved overlapping implementation file. It may differ only through approved exact old→new hunk supersessions checked by the shared checker.
- Arbitrary evaluator.md mutations still fail.
- `.loops/log.md` is protected from deletion, truncation, reordering, and rewriting. Authorized work may append required loop-history entries only.
- `.claude/agents/planner.md` is an approved implementation file. Its read-only agent tools prevent authoritative writes.
- Materialize the baseline in an executable test: copy `.loops/evidence/preexisting.patch` and `.loops/evidence/baseline-tests.txt` into the temporary archive, apply the copied patch there with `git apply --binary`, run `bash tests/run_tests.sh`, and record the exact pass count, failing criterion IDs, and full failure signatures in `.loops/evidence/baseline-tests.txt`. Run the same commands after the build. Require the current pass count to be at least 29/37 and current failure IDs to be a subset of `{5,11,14,21,34,35,36,37}`. Compare signatures only for failure IDs that remain. Protected files must retain baseline bytes. The current `.loops/log.md` must begin with the materialized baseline log bytes; remaining bytes may contain only new appended entries. Compare overlapping allowed files against the materialized baseline and confirm every pre-existing hunk remains.
- Do not claim that the existing linter satisfies the future all-diagnostics target. Repair and test that target after the build.

## Acceptance criteria

1. The dispatch protocol requires at least one subagent for every task and requires a completed explorer step before any builder dispatch.
2. The universal minimal dispatch path is exactly `explorer → builder` when the boundary is clear and no evaluator trigger applies.
3. A planner dispatch occurs only when the boundary is unclear, and the orchestrator records a written reason before making that call.
4. A fresh evaluator dispatch occurs for every harness, instruction, ambiguous, or correctness-critical change, including this repair.
5. Fan-out occurs only for truly disjoint work. The orchestrator records the disjoint file sets and the written reason for fan-out.
6. The orchestrator checks each requested agent's tools and scope before dispatch. It reroutes to a capable subagent when requirements exceed that agent's tools.
7. A tool-ceiling failure causes a changed reroute or a blocked result. The orchestrator never repeats the unchanged call.
8. Before planning or theory expansion for a production-data incident, the explorer runs the cheapest decisive read-only check when access exists. For object-freshness incidents, the check enumerates candidate relations and compares latest timestamps and state. A plan-only return is rejected when executable evidence was requested. Retries change the method or route.
9. Urgent work without a build uses the minimal explorer-only investigation. Any build still uses subagents and completes explorer before builder.
10. For read-only data or design questions, one explorer runs direct source checks and produces the answer. The orchestrator does not invoke `/run-loop`, contract negotiation, builder, or evaluator without requested code changes or a correctness-critical artifact. Unavailable required access is reported immediately.
11. Harness work does not replace the user's investigation or become the moving bottleneck. Harness repair receives one attempt, then the process returns to the original goal. A cycle with no source query and only `.loops/` changes is rejected.
12. The planner protocol states that the planner proposes the boundary but cannot write `.loops/contract.md` or other authoritative state when its tools prohibit writing.
11. The orchestrator, not the planner, builder, explorer, or evaluator, persists authoritative contract and run-state files after receiving structured proposals or reports.
12. Orchestrator builder dispatches supply exact acceptance criteria, approved files, and one named verify command.
13. A valid builder report uses these exact top-level separators in order: `BUILT:`, `files:`, `changes:`, `invariants:`, `within-plan:`, `verify:`, and `follow-ups:`. Each invariant names a criterion and gives PASS evidence.
14. A builder report is rejected before grading when it omits a separator, uses malformed separator syntax, reports a failed invariant, reports `within-plan: NO`, omits the named verify command, or lacks successful verify evidence.
15. The builder returns `BLOCKED` when requirements conflict, scope is unauthorized, or a required check fails. It never silently omits a requirement.
16. The orchestrator passes the raw builder report to the evaluator as advisory evidence only. It never treats `BUILT` as completion or as a grade.
17. Each contract attack round uses a fresh evaluator context. The evaluator attacks every criterion for testability, omissions, and false passes, and the loop repeats until objections are resolved or the run blocks.
18. The evaluator runs the named checks and grades every criterion independently. Only a fresh evaluator may return the final PASS verdict.
19. [Target-state, evaluated after build] The repaired prose linter reports every malformed acceptance-criteria line in one run, with its line number and full diagnostic text, and returns non-zero when any line fails. This is not a pre-lock condition, and the current linter is not assumed to pass it.
20. [Target-state, evaluated after build] The prose linter accepts valid numbered criteria, checkbox criteria, headings, blockquotes, and indented continuation lines without false diagnostics.
21. [Target-state, evaluated after build] The all-diagnostics fixture proves the linter reports multiple errors. Run:
    `fixture=$(mktemp -d); printf '%s\n' '## Goal' 'goal' '## Constraints' 'constraint' '## Acceptance criteria' 'bad first line' 'bad second line' '## Verify' '```bash' 'true' '```' > "$fixture/contract.md"; bash run.sh lint "$fixture/contract.md" > "$fixture/out" 2>&1; rc=$?; test "$rc" -ne 0; test "$(grep -c 'in acceptance criteria is bare prose:' "$fixture/out")" -eq 2`
    Expected result: exit non-zero and exactly two diagnostics naming lines 6 and 7.
22. [Target-state, evaluated after build] Static protocol checks confirm the documented orchestrator requires subagents, explorer-before-builder ordering, planner use only for unclear boundaries with a written reason, evaluator triggers, justified fan-out, capability checks, changed reroutes, and blocked unchanged retries. A fresh evaluator inspects observed trace and dispatch evidence for these transitions; tests do not claim that repository code intercepts Claude Agent calls.
23. [Target-state, evaluated after build] `bash tests/contract-negotiation.sh` exits 0 and prints `NEGOTIATION_OK` after exercising builder-report parsing and static protocol checks. The fixture may print `NEGOTIATION_BLOCKED` for documented failure evidence, but it must not simulate or claim enforcement of Agent dispatch.
24. [Target-state, evaluated after build] The evaluator independently inspects observed trace or dispatch evidence plus executable report and prose-lint checks. Evidence covers missing tools, tool-ceiling failures, changed reroutes, unchanged retry blocking, malformed reports, failed verification, scope violations, fresh evaluator context IDs, and multiple prose errors without adding a fake dispatch API.
25. [Target-state, evaluated after build] The repair changes only approved implementation files and evidence files, and preserves every pre-existing baseline path. An executable test copies `.loops/evidence/preexisting.patch` and `.loops/evidence/baseline-tests.txt` into a temporary archive, materializes the baseline, runs the recorded baseline test command, confirms protected files retain baseline bytes, confirms `.loops/log.md` is baseline-prefix plus append-only authorized entries, and confirms pre-existing hunks remain in overlapping allowed files. The final result must have at least 29/37 passes and failure IDs within `{5,11,14,21,34,35,36,37}`. Compare signatures only for failure IDs that remain.
26. [Target-state, evaluated after build] The final evaluator report lists every criterion with observed command evidence, a score, a verdict, the gap, and the exact checks run.
27. [Target-state, evaluated after build] The immutable baseline result in `.loops/evidence/baseline-tests.txt` records 29/37 passing and failures 5, 11, 14, 21, 34, 35, 36, and 37 with exact signatures. The expected repaired result is 34/37 with failures `{5,14,21}`. This expected improvement must not freeze the implementation or reject other improvements. The repair must not alter unrelated legacy expectations solely to obtain green. Acceptance also requires successful `bash .loops/verify.sh` and `bash tests/contract-negotiation.sh` checks.

## Verify

The lock verify command is:

```bash
bash .loops/verify.sh
```
