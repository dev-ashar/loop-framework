# Contract

> The graded boundary. The planner negotiates this with the user BEFORE any code
> is written. The evaluator grades ONLY against this file — not against vibes,
> not against the chat history. If the build is wrong, fix the build. If this
> file is wrong, that is the one time a human interrupts the loop.

Evidence base: `.loops/findings.md` (7 repos, gathered 2026-07-29). Every criterion is
tagged with the finding id it addresses. This file survived one adversarial evaluator
pass (BLOCK 0.22 → all nine defects remediated below).

## Goal

Harden the LOOPS harness with score persistence, self-linting contracts and logs, a
global cross-repo lesson store that a known past mistake demonstrably surfaces from, a
worktree skill that detects hazards and opens a draft PR containing the real fix, and
worktree-backed parallel builders — in that dependency order, each phase independently
landable, with a per-criterion shell test suite as the single source of truth for "done".

## Constraints

- All harness source changes live in `/Users/devashar/Documents/DS/workspace/loops`.
  Anything reaching another machine ships via this repo's `install.sh`.
- Every numbered acceptance criterion below has exactly one corresponding test function
  in `tests/run_tests.sh`. A criterion with no test is a failed build, not a soft miss.
- Dependency order is fixed: Phase 1 → Phase 2 → Phase 3 → Phase 4. Phase 4 cannot land
  before Phase 3, because N builders in one working tree collide.
- Landing is phase-by-phase. Each phase runs build→grade to PASS autonomously, then the
  orchestrator reports and pauses before starting the next phase.
- Finding E behaviour is correct and must not be weakened: the adversarial evaluator's
  posture, "land-on-PASS / gate deploy separately", and `.running`-at-PASS as a human
  gate. No new script may auto-clear `.running`. Criterion 23 enforces this.
- The default turn-based fast path gains ZERO new ceremony: no new mandatory hook, no
  new required file, no added latency for a plain edit-and-check turn.
- `run.sh` stays POSIX-ish bash. `jq` is the only new hard dependency (verified present:
  jq-1.7.1-apple). Test fixtures must use BSD `touch`/`date` syntax — this machine has
  BSD coreutils and GNU `touch -d` / `date -d` forms fail.
- The lesson store is GLOBAL at `~/.claude/memory/lessons.jsonl`, shared by all repos.
  Rationale: both documented repeat-mistakes are the same class in different repos, so a
  per-project store would structurally never have caught them.

### Non-goals

- Migrating or committing anything into the 6 downstream repos as part of THIS run. The
  worktree skill's fix-and-PR capability is built and tested against synthetic fixture
  repos only; pointing it at a real repo is a separate, explicitly-invoked action.
- Enforcing C3 (harness bypass) with a blocking hook — that would add fast-path
  ceremony. A non-blocking `multireport` warning is in scope (criterion 15), nothing more.
- True RL, gradient descent, embeddings, fine-tuning, or a vector store. The learning
  substrate is a flat, greppable, append-only JSONL plus prompt wiring that reads it —
  deliberately dumb and auditable (rule 8).
- Any new agent role beyond the existing four. "Parallel builders" means more instances
  of the existing `builder`, not a new tier.
- A GUI or dashboard. `multireport` is text from a CLI.
- Auto-merging without an evaluator grading the merged result; auto-resolving conflicts.
- Auto-committing any secret. Criterion 30 makes this a hard failure.
- Proving an LLM agent will *actually obey* a prompt at runtime. Grep-based criteria
  assert the instruction text exists and is affirmative (not negated) — they cannot
  assert model behaviour. Stated plainly, not hidden.

## Acceptance criteria

> One test function per numbered criterion in `tests/run_tests.sh`, named
> `test_criterion_<n>`. Bracket tag is the finding id from `findings.md`.

### Phase 0 — the test harness itself

- [ ] 1. `tests/run_tests.sh` exists, is executable, defines exactly one function named
  `test_criterion_<n>` for every n in 2..38, prints one line per criterion in ascending
  order matching `^\[(pass|FAIL)\] criterion <n>: .+$`, and ends with `37/37 passed`.
  Any n in 2..38 with no printed line fails criterion 1 itself. Check: run the suite,
  assert 37 criterion lines present, assert the ascending order, assert the final tally.

### Phase 1 — foundations

- [ ] 2. `[C4]` `templates/feature_list.json` gains a `metric.history` array, empty by
  default. Check: `run.sh init` in a temp dir, `jq '.metric.history'` returns `[]`.
- [ ] 3. `[C4]` `run.sh score record <iter> <score> <verdict>` appends
  `{iteration, score, verdict, ts}` to `.loops/feature_list.json`'s `metric.history`.
  Check: call twice, assert length == 2, assert all four keys round-trip via `jq`.
- [ ] 4. `[C4]` `run.sh score stall` exits 2 and prints `STALL` when the last two history
  entries are non-increasing in score; exits 0 otherwise. Check: `[0.5, 0.5]` → exit 2;
  `[0.5, 0.4]` → exit 2; `[0.5, 0.8]` → exit 0.
- [ ] 5. `[C4]` `.claude/skills/run-loop/SKILL.md` step 2 contains a line matching
  `run\.sh score record` and a line matching `run\.sh score stall`, each passing the
  **anti-negation guard** defined once here and reused by criteria 11, 20, 21, 22, 23,
  36, 37: no negation token (`not\b|never\b|avoid\b|don't\b|do not\b|optional\b|skip\b`,
  case-insensitive) may appear anywhere in the ±2-line window around the match —
  the two lines before, the matched line itself, and the two lines after. (A
  preceded-only guard is defeated by negating on the following line; the window is
  bidirectional for that reason.) Check: extract step 2's span, apply the window guard.
- [ ] 6. `[C5]` `run.sh reap` is read-only. Fixture `.loops/.running` backdated with
  `touch -t "$(date -v-50H +%Y%m%d%H%M)"` and last history `verdict: PASS` → prints
  `AWAITING LANDING APPROVAL`, exits 0, `.running` still present with identical sha256.
- [ ] 7. `[C5]` Same fixture with last `verdict: BLOCK` (or empty history) → prints
  `STALE`, exits 1, `.running` still present with identical sha256.
- [ ] 8. `[C5]` `run.sh reap` deletes, moves, or truncates `.running` under no code path.
  This must be checked **behaviourally, not by grepping the source** — a source grep for
  `rm`/`unlink`/`>` is defeated by `f=.running; rm -f "$D/$f"`, `find .loops -name .running
  -delete`, or `mv`. Check: on a fixture whose `.loops/` contains `.running` plus two
  sentinel files, run `reap` in all three modes (`AWAITING`, `STALE`, and against a
  `.loops/` with no `.running` at all), then assert for every mode that `ls -a .loops/` is
  byte-identical to before, `.running`'s sha256 and its `stat` mtime and inode are
  unchanged, and no `.running.*` sibling was created. Any mode that mutates the directory
  listing FAILS.
- [ ] 9. `[C2]` `run.sh lint [path]` exits 0 only if the target contract contains
  `## Goal`, `## Constraints`, `## Acceptance criteria`, and a heading beginning
  `## Verify`; the Verify section contains a fenced code block; and, within the
  Acceptance-criteria section, every non-blank line is either a heading (`^#{2,4} `), a
  blockquote (`^> `), a `- [ ]`/`- [x]` item, or a continuation line indented ≥2 spaces.
  Any other non-blank line is a violation, reported with its line number. Every one of the
  listed conditions needs its own discriminating fixture, so no sub-check can be silently
  unimplemented. Check, five fixtures: (a) a valid fixture → exit 0; (b) bare prose
  paragraph in the criteria section → non-zero, naming the line number; (c) missing
  `## Verify` heading → non-zero, naming the heading; (d) missing `## Goal` → non-zero,
  naming it, and separately missing `## Constraints` → non-zero, naming it; (e) a present
  `## Verify` section containing **no** fenced code block → non-zero. A lint that never
  implements the Goal/Constraints presence check or the fenced-block check FAILS (d) or (e).
- [ ] 10. `[C2]` `run.sh lint .loops/contract.md` exits 0 on THIS file. Check: run it.
  (This file uses `### Phase N` headings, never bold pseudo-headers, inside the criteria
  section, specifically so it satisfies criterion 9's algorithm.)
- [ ] 11. `[C2]` `.claude/skills/contract/SKILL.md`'s Lock step contains a line matching
  `run\.sh lint`, not negated per criterion 5's guard. Check: extract the Lock step span,
  grep with the anti-negation guard.
- [ ] 12. `[C6]` `run.sh log "<op>" "<title>"` appends a line to `.loops/log.md` matching
  `^## \[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] .+ \| .+$`. Check: call it, grep
  the appended line against that exact regex.
- [ ] 13. `[C6]` `run.sh lint` validates **every** `^## \[` line in `.loops/log.md` against
  that regex and fails naming each offending line. Must be general parsing, not a
  special-case match on one known string. Check with four fixture lines, each in its own
  fixture so the failure is attributable: (a) the exact data-catalog drift
  `## [2026-07-25] act | dedup fix applied` (time dropped) → FAIL naming it; (b)
  `## [2026-07-25 20:35] act dedup fix applied` (missing the ` | ` separator) → FAIL;
  (c) `## [not-a-date 20:35] act | x` (unparseable date) → FAIL; (d) a well-formed
  `## [2026-07-25 20:35] act | dedup fix applied` → PASS. A lint that hardcodes fixture
  (a)'s string passes (a) but fails (b) and (c) and therefore fails criterion 13.
- [ ] 14. `[C3 guard]` No new and no altered blocking hook. The baseline is **pinned here,
  in the contract text, from the pre-build tree state** (verified clean in git at
  negotiation time) — it is NOT generated by the build, because a build-generated baseline
  is a tautology the build itself can rewrite:
  - `.claude/hooks/pre-tool-use.sh`  → `310499bb8919f84661131adbd243a124ad2329a0f73140a4f5c1380515e043cc`
  - `.claude/hooks/post-tool-use.sh` → `b8b65b36bddcbe700b48850f4feef7f8ddac2561e620c25d7de9ca67821e8e78`
  - `.claude/hooks/stop.sh`          → `3419ac17dce751736b0f33f2b9aa484776e26219b9f22a1a141c85d71093c77e`

  Check, both parts required: (a) `shasum -a 256` of each of the three paths equals the
  literal above, with the expected values read from the contract or hardcoded in the suite,
  never recomputed from the files under test; (b) `.claude/hooks/` contains **exactly** those
  three files — any additional file there FAILS, closing the "add a fourth blocking hook"
  hole. `tests/fixtures/make-baseline.sh` is not part of this criterion and must not exist
  as its source of truth. If a hook legitimately needs to change, the contract must be
  re-negotiated and these literals updated by a human — that is the intended friction.
- [ ] 15. `[C3]` `run.sh multireport <repo-path>...` prints one row per repo with worktree
  count, dirty-file count, `.running` state, and log-format-ok(y/n); prints a
  non-blocking `WARN: no contract.md` for any repo having a `.loops/log.md` with ≥1 entry
  but no `contract.md` (the data-solutions-kujata bypass shape); exits 0 even when
  warning. Check: two self-created fixture repos with **deliberately distinct, known**
  states — repo A: 2 worktrees, 3 dirty files, `.running` present, well-formed log; repo B
  (bypass shape): 1 worktree, 0 dirty files, no `.running`, log with ≥1 entry and no
  `contract.md`. Assert each printed row's four field values equal those known values for
  the right repo, that the `WARN: no contract.md` line appears for B and **not** for A,
  exit 0, and `git status --porcelain` in each is byte-identical before/after. A stub
  printing a fixed row FAILS on the value comparison.

### Phase 2 — learning substrate

- [ ] 16. `[C1]` `install.sh` creates `~/.claude/memory/lessons.jsonl` idempotently if
  absent and never truncates it if present. Check with a stubbed `$HOME`: first run
  creates it; a second run with a pre-seeded line leaves that line count unchanged.
- [ ] 17. `[C1]` `run.sh lesson record --category <cat> --mistake "<t>" --correction "<t>"
  [--source <path>]` appends exactly one JSON object with those four keys plus `ts`.
  Check: record one, `jq` the last line, assert every field round-trips, assert the file
  gained exactly one line.
- [ ] 18. `[C1]` `run.sh lesson check "<free text>"` tokenizes the query on non-alphanumerics,
  lowercases, drops a stopword list, and matches an entry when ≥2 distinct non-stopword
  tokens appear in that entry's `mistake` or `category`. It prints matching `correction`
  values to stdout, exits 0 on ≥1 match and 1 on none. Check: the algorithm's threshold
  is observable — a query sharing exactly 1 non-stopword token with a seeded lesson must
  exit 1, and one sharing 2 must exit 0.
- [ ] 19. `[C1 — the falsifiable core]` Seed the store with the two real C1 lessons:
  (a) category `external-data-source`, mistake containing `cashPnl is net-of-fees`,
  correction naming the gross/net split; (b) same category, mistake containing
  `HL-side quantities are always NULL`. Then all three must hold:
  `lesson check "reconcile the polymarket PnL API cashPnl field"` prints the (a)
  correction and exits 0; `lesson check "rename a CSS variable"` exits 1; and the hard
  negative `lesson check "verify the quantity field is correct"` — which shares the
  generic token *quantit\** with lesson (b) but nothing of its substance — also exits 1.
  This proves retrieval surfaces the documented past mistake without firing
  indiscriminately. It does NOT prove any agent reads or obeys it.
- [ ] 20. `[C1]` `.claude/agents/evaluator.md` contains a line matching
  `run\.sh lesson record --category external-data-source`, not negated per criterion 5's
  guard, instructing the evaluator to record a lesson on `REVIEW: BLOCK` whose gap traces
  to an unverified external API or data-source assumption.
- [ ] 21. `[C1]` `.claude/skills/contract/SKILL.md`'s Boundary step contains a line
  matching `run\.sh lesson check` (not negated) and the literal `external-data-source`,
  requiring that on a match a mandatory acceptance criterion be added of the form
  "verify <external system>'s exact semantics via a live read-only check before locking".
- [ ] 22. `[C1]` `.claude/agents/planner.md` contains a line matching `run\.sh lesson check`,
  not negated per criterion 5's guard.
- [ ] 23. `[E guard]` The adversarial framing survives every Phase-2 edit.
  `.claude/agents/evaluator.md`'s opening instruction still asserts the work is broken and
  the evaluator's job is to prove it. Check: grep the file for a line matching
  `broken` AND a line matching `prove it`, both within the first 15 lines, with the
  anti-negation guard applied.

### Phase 3 — worktree hazard detection, remediation, and PR

- [ ] 24. `[D]` `.claude/skills/worktree/SKILL.md` exists with frontmatter `name: worktree`,
  documents the `check`, `provision`, and `fix` subcommands, and states all three fail
  closed on a dirty tree unless `--force` is passed.
- [ ] 25. `[D]` `run.sh worktree check [path]` is read-only and emits one machine-readable
  token per detected hazard from this fixed vocabulary: `HARDCODED_HOOK_PATH`,
  `HOOKS_PATH_ABSOLUTE`, `MISSING_ENV_FILE`, `MISSING_BOOTSTRAP_ARTIFACT`. Fixture repo
  has all four: (a) a `pre-commit` hook containing a hardcoded absolute path, (b)
  `core.hooksPath` set absolute, (c) a gitignored `.env` present on disk and referenced by
  a bootstrap script, (d) a gitignored-but-present build/dependency dir from the set
  `node_modules/`, `.terraform/`, `env/`, `venv/`, `.venv/` — the classes findings.md §D.2
  documents as absent-in-a-fresh-worktree. Check, all three fixtures required — a
  `check` that unconditionally echoes the vocabulary must FAIL:
  (a) *all-hazards fixture* — all four exact tokens appear in stdout;
  (b) *clean fixture* — a repo with none of the four hazards prints **none** of the four
  tokens (a token-free stdout, or explicitly zero hazards);
  (c) *strict-subset fixture* — a repo triggering exactly two of the four prints those two
  and **not** the other two, asserted by name;
  and in all three, `git status --porcelain` is byte-identical before/after.
- [ ] 26. `[D]` `run.sh worktree provision <branch>` on a hazardous fixture exits non-zero
  and creates no new worktree directory when `--force` is absent (fail-closed default) —
  **and succeeds without `--force` when there are no hazards**, so an always-fail-closed
  stub cannot pass. Check, both fixtures: (a) hazardous fixture → exit non-zero and
  `git worktree list | wc -l` unchanged; (b) clean fixture on which `worktree check`
  reports zero hazards → `provision <branch>` with no flags exits 0, the worktree
  directory exists on disk, `git worktree list` gained exactly one entry, and `<branch>`
  is checked out in it.
- [ ] 27. `[D]` `worktree provision <branch> --force` creates the worktree despite hazards,
  printing every detected hazard token to stdout before creating it. Check: worktree
  directory exists on disk and all applicable tokens appear in output.
- [ ] 28. `[D]` `run.sh worktree fix` remediates `HARDCODED_HOOK_PATH` by rewriting the
  absolute path to one derived from **`dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)"`**
  — the main worktree — and NOT from `git rev-parse --show-toplevel`. Empirically verified:
  from inside a linked worktree `--show-toplevel` resolves to the linked worktree, where the
  shared `env/` does not exist, so a `--show-toplevel`-derived fix still breaks every commit
  from a fresh worktree. Check, in two parts, both required:
  (a) *syntax* — after `fix` the hook contains no absolute `/Users/` path, is still
  executable, `bash -n` parses clean, and the hook body contains no `--show-toplevel`;
  (b) *functional* — create a real linked worktree off the fixture, run the fixed hook's
  interpreter-resolution from inside it, and assert the resolved path exists and is
  executable. A build that satisfies (a) but not (b) FAILS criterion 28.
- [ ] 29. `[D]` `run.sh worktree fix` remediates `HOOKS_PATH_ABSOLUTE` by unsetting the
  absolute `core.hooksPath`. Check: after `fix`, `git config --get core.hooksPath` is
  empty or relative, and a subsequent `worktree check` no longer emits that token.
- [ ] 30. `[D — hard safety gate]` `worktree fix` and `worktree provision --pr` NEVER stage
  or commit a file matching any pattern in this **secret set**: `.env*`, `*.pem`, `*.key`,
  `*secret*`, `*credential*`, `id_rsa*`, `id_ed25519*`, `.npmrc`, `.netrc`, `.pgpass`,
  `*.tfvars`, `*.p12`, `*.pfx`, `*.keystore`, `*.jks`, and cloud service-account JSON
  (`*service-account*.json`, `*-sa.json`, `gcloud-*.json`). This set is defined once here
  and reused by criterion 38 only. `MISSING_ENV_FILE` is reported for a human, never
  auto-fixed. Check: fixture seeded with one present-on-disk file per pattern in the set;
  after `fix` and a stubbed `--pr` run, assert `git diff --cached --name-only` and the
  branch's full commit tree (`git log --name-only`) contain no path matching any pattern,
  and that each seeded file remains untracked.
- [ ] 31. `[D]` `worktree provision <branch> --pr` commits the remediation produced by
  `fix`, invokes `gh pr create --draft`, and records the returned PR URL into `.loops/log.md`
  via `run.sh log`. The `gh pr create` invocation must receive a non-empty `--body` (or
  `--body-file` whose file is non-empty) naming every hazard token that `worktree check`
  emitted for that repo. Check: stub a fake `gh` earlier on `PATH` that prints a fixed URL
  and dumps its own argv to a file; assert the branch's HEAD commit diff is non-empty and
  contains the hook fix, the URL appears in the fixture's `log.md`, and the captured argv
  contains `--draft` plus a body naming **exactly** the tokens the fixture triggered — every
  triggered token present AND every untriggered token absent. Run this against criterion
  25's strict-subset fixture specifically, so a body that always lists all four tokens
  FAILS. An empty or token-free body also FAILS.
- [ ] 32. `[B]` `run.sh worktree reap [path]` reports orphaned/prunable worktrees via
  `git worktree list --porcelain` and prunes them ONLY with `--prune`; without that flag
  it is read-only. Check, both fixtures required: (a) a worktree whose directory was
  deleted → default run reports it by path and leaves the `.git/worktrees/` entry intact;
  `--prune` removes the entry; (b) a **clean** fixture with only live worktrees → the run
  reports zero orphans and names none, so an implementation that always claims an orphan
  FAILS.
  (Addresses finding B: 12 worktrees across the 7 repos, nothing reaps them.)
- [ ] 33. `[D non-goal guard]` The suite performs no remediation against any of the 6 real
  repos. Check: for each named repo path that exists, `git status --porcelain` and
  `git rev-parse HEAD` are identical before and after the whole suite run; SKIP (not FAIL)
  for any absent path.

### Phase 4 — parallel builders

- [ ] 34. `[C7]` `run.sh scope-check <worktree-path> <base-ref> <allowed-file-list>` exits 0
  iff the worktree's **full divergence from `<base-ref>`** is a subset of the allowed list,
  else exits 1 naming the offending path(s). The path set is the union of committed and
  uncommitted change: `git -C <path> diff --name-only "$(git -C <path> merge-base <base-ref> HEAD)"`
  (which covers commits on the branch **and** the working tree) plus
  `git -C <path> ls-files --others --exclude-standard` (new untracked files). A bare
  `git diff --name-only` is explicitly insufficient and FAILS this criterion: by the time
  criterion 36's merge step runs, a parallel builder's work is committed and the working
  tree is clean, so a working-tree-only diff is empty and the guard would be a no-op
  exactly when it matters. Check, all four fixtures required: (a) in-scope **committed**
  edit → exit 0; (b) out-of-scope **committed** edit → exit 1 with the offending path
  named in stdout; (c) out-of-scope **uncommitted** edit → exit 1 naming it; (d)
  out-of-scope **new untracked** file → exit 1 naming it.
- [ ] 35. `[C7]` `run.sh merge-worktrees <target-branch> <branch1> [branch2 ...]`
  sequentially `git merge --no-ff`s each branch into target, stopping at the first conflict
  with non-zero exit and the conflicting branch named, leaving the repo mid-merge with no
  auto-abort. Check: two non-conflicting fixture branches merge with both changes present
  in target; two conflicting branches stop non-zero with conflict markers on disk.
  (Verified feasible: merging a branch checked out in a linked worktree succeeds.)
- [ ] 36. `[C7]` `.claude/skills/run-loop/SKILL.md` contains a `### Parallel builders`
  section stating that when the locked plan has ≥2 builder steps over disjoint file sets,
  the orchestrator provisions one worktree per step, dispatches that many `builder` agents
  in a single message, then runs `scope-check` per worktree and `merge-worktrees` before
  the evaluator grades. Check: extract the span from `### Parallel builders` to the next
  `##`/`###` heading; assert `worktree provision`, `scope-check`, and `merge-worktrees`
  all appear inside that span, each passing the anti-negation guard.
- [ ] 37. `[C7 fast-path guard]` The single-builder fast path is documented as
  ceremony-free: when the plan has exactly one builder step, no worktree is provisioned and
  `builder` is dispatched in place exactly as today. Check: the guard sentence appears
  inside the `### Parallel builders` span or within 3 lines after its closing line, **and
  passes the criterion-5 anti-negation guard** — with the single exception that the tokens
  `not`, `no`, and `skip` are permitted when they occur in the phrase describing what is
  *omitted for the single-builder case* (e.g. "no worktree is provisioned"); the guard is
  applied to the surrounding ±2-line window with that one phrase masked out. Any negation
  attaching to the parallel protocol itself still FAILS.
- [ ] 38. `[D — hard safety gate]` `worktree fix` and `worktree provision --pr` stage ONLY
  the paths they themselves modified: every staging call is an explicit `git add <path>`
  with a literal path argument, never `git add -A`, `git add .`, `git add -u`, nor
  `git commit -a`. Check, both parts required: (a) *static* — no `git add -A`, `git add .`,
  `git add -u`, `git commit -a`, or `commit -am` appears in `run.sh`; (b) *behavioural* —
  on a fixture carrying an unrelated dirty tracked file plus an unrelated untracked file
  (neither in the secret set of criterion 30), run `fix` and the stubbed `--pr`, then assert
  the resulting commit's `git show --name-only` lists only the hook path(s) the remediation
  touched, and that both unrelated files are still dirty/untracked afterwards.

## Verify command

```
bash /Users/devashar/Documents/DS/workspace/loops/tests/run_tests.sh
```

PASS requires BOTH:
(a) the command above exits 0, prints one `[pass] criterion <n>` line for every n in
    2..38 in ascending order, and ends with `37/37 passed`; AND
(b) the evaluator independently re-runs, via its own Bash calls and not via the suite's
    self-report, the six criteria most prone to trivial satisfaction — 10 (contract
    self-lint), 19 (lesson retrieval incl. both negatives), 25 (hazard tokens), 28
    (functional hook fix from inside a real linked worktree), 30 (secret-commit gate),
    and 38 (no blanket staging) — and confirms each holds.

Any non-zero exit, any `[FAIL]` line, any missing criterion line, or any disagreement in
(b) is BLOCK. The suite is self-contained: it creates its own temp git repos and `.loops/`
fixtures under `mktemp -d`, depends on real 6-repo state only for the read-only guards in
criteria 15 and 33 (which SKIP when a path is absent), and cleans up after itself.

## Ordered build plan

Landing is phase-by-phase: each phase runs build→grade to PASS, then the orchestrator
reports and pauses.

**Phase 1 — foundations** (C2, C4, C5, C6)
1. `[explorer]` Grep `.claude/**`, `install.sh`, `run.sh` for existing consumers of
   `feature_list.json` and of the `run.sh` dispatch, so extending them breaks nothing.
2. `[builder]` Extend `templates/feature_list.json` (`metric.history`) and `run.sh`
   (`score record`, `score stall`, `reap`, `lint`, `log`, `multireport`).
   Files: `run.sh`, `templates/feature_list.json`.
3. `[builder]` Update `.claude/skills/run-loop/SKILL.md` (score wiring) and
   `.claude/skills/contract/SKILL.md` (lint gate at Lock). Files: those two only —
   disjoint from step 2, **parallelizable with it**.
4. `[builder]` Write `tests/run_tests.sh`; cover criteria 1–15. The criterion-14 hook
   hashes are hardcoded from the contract text — do NOT write a baseline generator.
   Sequenced after 2–3.

**Phase 2 — learning substrate** (C1)
5. `[builder]` `install.sh` step for `~/.claude/memory/lessons.jsonl`; `run.sh lesson
   record|check` with the tokenize/stopword/≥2-overlap algorithm. Files: `install.sh`, `run.sh`.
6. `[builder]` Wire `.claude/agents/evaluator.md`, `.claude/agents/planner.md`, and
   `.claude/skills/contract/SKILL.md` (Boundary). Files: those three — disjoint from step
   5, **parallelizable with it**. Must not disturb evaluator.md's adversarial opening (23).
7. `[builder]` Extend the suite with criteria 16–23.

**Phase 3 — worktree** (D, B)
8. `[explorer]` Confirm no hazard classes beyond `findings.md` §D exist in the 6 repos'
   `.git/hooks/` and `core.hooksPath`. Read-only.
9. `[builder]` New `.claude/skills/worktree/SKILL.md`; `run.sh worktree check|provision|fix|reap`
   with `--force`, `--pr`, `--prune`. Files: `run.sh`, the new SKILL.md.
10. `[builder]` Extend the suite with criteria 24–33 **and 38** (both hard safety gates: 30
    secret-commit, 38 no-blanket-staging; 38 is numbered last but belongs to this phase).

**Phase 4 — parallel builders** (C7 — hard-depends on Phase 3)
11. `[builder]` `run.sh scope-check`, `run.sh merge-worktrees`. File: `run.sh`.
12. `[builder]` Update `.claude/skills/run-loop/SKILL.md` with the parallel protocol and
    the fast-path guard. File: that SKILL.md — **parallelizable with step 11**.
13. `[builder]` Extend the suite with criteria 34–37.

## Known weaknesses (stated, not hidden)

- Criterion 19 proves a keyword-retrieval mechanism surfaces a seeded lesson and stays
  quiet on two unrelated queries, one of which shares a generic token. It cannot prove an
  agent acts on it. The "RL / self-learning" framing has no true analog here: this is a
  lookup table plus prompt instructions, labelled as such rather than dressed up.
- Criteria 5, 11, 20, 21, 22, 23, 36, 37 are grep-on-markdown checks hardened with an
  anti-negation guard. The guard closes the "prompt says the opposite" hole the evaluator
  found, but still cannot prove runtime obedience. Residual risk is real and accepted.
- Phase 4's merge is sequential `--no-ff` with fail-on-conflict. It does no semantic
  conflict detection: two builders can produce individually-clean, jointly-wrong changes,
  which only the evaluator's grade on the merged result catches.
- `worktree fix` remediates two hazard classes. `MISSING_ENV_FILE` is deliberately not
  auto-fixable (criterion 30) — secrets stay a human step.
