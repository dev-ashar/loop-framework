# Progress

Stage: PHASE 3 COMPLETE (PASS 1.00). Landing, then Phase 4.

Goal: improve the LOOPS harness — more agents in parallel, self-learning agents,
automated worktree management, fix the common errors found across 7 repos.
Contract: `.loops/contract.md` (38 criteria). Landing phase-by-phase.

## Status

| Phase | Scope | Criteria | Score | Verdict |
|---|---|---|---|---|
| 1 | Foundations - score persistence, lint, reap, multireport | 2-15 | 1.00 | PASS, landed `c2ef3d5` |
| 2 | Learning substrate - global lesson store | 16-23 | 1.00 | PASS, landed `bba160b` |
| 3 | Worktree management + draft-PR fix | 24-33, 38 | 1.00 | PASS, landing now |
| 4 | Parallel builders | 34-37 | - | not started |

Suite: `bash tests/run_tests.sh` reports 33/37. The 4 failures are criteria 34-37,
which print honest `not yet implemented (phase 4)` stubs.

## Phase 3 - what landed

`run.sh worktree check|provision|fix|reap` plus the draft-PR path. `check` is
read-only and emits four hazard tokens computed from repo state: HARDCODED_HOOK_PATH,
HOOKS_PATH_ABSOLUTE, MISSING_ENV_FILE, MISSING_BOOTSTRAP_ARTIFACT. `provision` fails
closed on hazards unless `--force`; `--pr` applies the fix, stages only the hook file
by explicit path, commits a body naming exactly the triggered hazards, and opens a
draft PR. `fix` rewrites absolute interpreter paths in hooks to `$MAIN_WT`-relative
form and unsets an absolute `core.hooksPath`. `reap` reports orphaned worktrees and
prunes only with `--prune`. New skill at `.claude/skills/worktree/SKILL.md`.

Safety gates hold, verified behaviourally by the evaluator with its own fixtures:
no file matching the criterion-30 secret set is ever staged or committed;
MISSING_ENV_FILE is reported for a human, never auto-fixed; no `git add -A|.|-u` and
no `git commit -a` anywhere in `run.sh`; the 6 downstream repos end byte-identical.

## Phase 3 - four defects, all caught by the evaluator

Three build/grade iterations. Every defect was found by the separated evaluator with
its own fixtures — none by the orchestrator, none self-reported by a builder. Two of
the four were cases where a builder's own summary asserted something its code did not
do.

1. **Criterion 28, wrong root.** `fix` used `git rev-parse --show-toplevel`, but
   `provision --pr` calls `fix` after `cd`-ing into the linked worktree, so it
   resolved to the linked worktree on every real invocation. Now derived from
   `--git-common-dir`. This is the exact fact the criterion was rewritten to encode
   during negotiation, and the build still got it wrong.
2. **Criterion 28, silent corruption.** The awk rewriter had a heuristic
   5-component-path fallback that dropped the filename on shorter paths
   (`/Users/x/y/tool` → `INSTALL_TOOL=$MAIN_WT`), producing a hook that broke at
   commit time with no error at fix time. Now prefix-strips, and fails loudly with a
   non-zero exit leaving the hook byte-unchanged when a path is not repo-rooted.
3. **Criterion 33 was a tautology.** It captured before/after state at the same
   instant with the comment "we trust the suite has no side effects" — the criterion
   exists to verify that trust. Now snapshots all 6 repos once before any criterion
   runs and diffs at the end. 5 repos are live coverage; only `infrastructure` is
   genuinely absent.
4. **Suite leaked real git repos, twice over.** `fresh_home_tmp()` appended to a
   `HOME_TMPDIRS` array from inside `d=$(fresh_home_tmp)` — command substitution runs
   in a subshell, so the array never reached the parent, the trap iterated over
   nothing, and 7 `loops-test.*` git repos accumulated in `~/.cache` every run. Fixed
   with a registry file. Behind it: `trap cleanup EXIT INT TERM` does not terminate
   in bash — the handler runs and execution *continues* — so cleanup deleted
   `SUITE_TMPDIR` mid-run, later registry appends silently failed, and the suite
   crashed on `set -u`. Fixed with a dedicated `on_signal` handler exiting 130/143 and
   a `CLEANUP_DONE` guard. SIGINT had passed by luck of signal timing; SIGTERM
   exposed it.

Defects 4a and 4b are now lessons in the global store, so the Phase-2 machinery paid
for itself in the same session it landed. Store holds 3 entries.

## Carried forward - real gap, not scheduled

`worktree check`'s hazard prefilter greps for the literal `/home/`, so interpreter
paths like `/opt/homebrew/bin/python3.12` never reach the scan and are invisible to
it. Found by a builder. The pattern set is contract-defined, so it stays as-is this
run rather than being amended mid-grade. Worth a Phase-5 criterion.

Also unwired: `run.sh lint` is reachable only by explicit path; nothing calls it
automatically.

## Next

Phase 4 - parallel builders (criteria 34-37). This is the payoff for Phase 3: N
builders in one tree collide, so worktrees gate concurrency. Criterion 34 requires
`scope-check` to use `git diff --name-only "$(git merge-base <base> HEAD)"` union
`git ls-files --others --exclude-standard` — a bare `git diff --name-only` was proven
insufficient with a real fixture during negotiation and explicitly fails the
criterion.
