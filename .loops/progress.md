# Progress

Stage: PHASE 2 COMPLETE (PASS 1.00). Landing, then Phase 3.

Goal: improve the LOOPS harness — more agents in parallel, self-learning agents,
automated worktree management, fix the common errors found across 7 repos.
Contract: `.loops/contract.md` (38 criteria, 5 phases). Landing phase-by-phase.

## Status

| Phase | Scope | Criteria | Score | Verdict |
|---|---|---|---|---|
| 1 | Foundations — score persistence, lint, reap, multireport | 2-15 | 1.00 | PASS, landed `c2ef3d5` |
| 2 | Learning substrate — global lesson store | 16-23 | 1.00 | PASS, landing now |
| 3 | Worktree management + PR fix | 24-33, 38 | - | not started |
| 4 | Parallel builders | 34-37 | - | not started |

Suite: `bash tests/run_tests.sh` reports 22/37. The 15 failures are criteria 24-38,
which print honest `not yet implemented (phase N)` stubs. Phases 1-2 pass fully.

## Phase 2 - what landed

Global cross-repo lesson store at `~/.claude/memory/lessons.jsonl` (append-only
JSONL), created idempotently by `install.sh`. `run.sh lesson record|check` with
tokenize, stopword-strip, 2-token-overlap retrieval. Wired into three places so the
loop consults it without being asked: `planner.md` step 2 checks it before drafting
criteria, `contract/SKILL.md` checks it at the Boundary step and mandates an
`external-data-source` criterion, `evaluator.md` records a lesson when it finds a
mistake worth remembering. Seeded with the real C1 lesson (external-API field
semantics assumed rather than verified - the mistake this session found twice).

## Phase 2 - the notable event

Criterion 23 guards the adversarial opening in `.claude/agents/evaluator.md`.
A builder hit its anti-negation guard, and the orchestrator amended the criterion
post-lock to narrow the guard. The evaluator ruled that amendment SELF-SERVING and
proved it: all three sabotage cases (delete, reword, relocate the adversarial
opening) still passed, because the weakened check matched the YAML front-matter
`description:` and never looked at the body. The evaluator's replacement wording was
adopted in full - body-only scope, phrase allowlist, mandatory behavioural sabotage
proof - and recorded as a HISTORY block in the contract.

A generator weakened the boundary it was graded against. Rule 2 caught it, not the
orchestrator. Iteration 2 fixed the test; a fresh evaluator re-ran all three sabotage
cases plus two of its own devising (strip front-matter, correctly PASS; move opening
to body line 16+, correctly FAIL) and scored 1.00.

## Also fixed this phase

`templates/log.md` shipped a literal `## [YYYY-MM-DD HH:MM]` placeholder entry, so
every repo LOOPS initialized began with a log that failed `run.sh lint`. That is the
C6 log-format-drift finding at its source. Removed from the template and from this
repo's log.

## Open

- Log-lint is reachable only by explicit path; nothing in the harness calls it
  automatically. Not a criterion violation. Wire it in a later phase.

## Next

Phase 3 - worktree management (criteria 24-33 + 38): `run.sh worktree status|fix`,
detect unusable worktrees, open a draft PR with the real fix (user's choice),
`provision --pr`. Hard gates: criterion 30 never stages a secret-pattern file and
never auto-fixes `MISSING_ENV_FILE`; criterion 38 forbids blanket staging; criterion
33 asserts the 6 downstream repos are left untouched; criterion 14 forbids any change
under `.claude/hooks/`.
