# Progress

## Run: Phase 5 — engine + model configuration CLI, on two real parallel builders
Contract: `.loops/contract.md` (20 criteria, locked 2026-08-05)
Result: **PASS 1.00** at iteration 4. Evaluator: converged, no gap.
Roster: two luna builders in parallel, terra graded every round, opus orchestrated.

This is the run Phase 4 was built for. The gates fired instead of merely existing.

## Score trace
- iter 1 — BLOCK. CRLF defect: `engine.sh` frontmatter awk compared `$0 == "---"`,
  LF-only, while `models.sh` already stripped `\r`. Two libraries, one format, two
  parsers — the shared-interface criterion was too weak to catch it.
- iter 2 — BLOCK. `cmd_engine run` invoked the engine as a child process, so the
  caller continued afterwards. Fixed with `exec`; all validation moved before it.
- iter 3 — BLOCK. `response=$(curl ...)` in `lib/models.sh` died under run.sh's
  inherited `set -euo pipefail` before its own diagnostic branch could run.
- iter 4 — PASS 1.00. Both curl call sites wrapped as
  `if response=$(...); then curl_status=0; else curl_status=$?; fi`, with a
  fake-curl regression test in `verify.sh` covering both.

## What landed
- **`run.sh models {list|available|set}`** — reads and rewrites the `model:` key in
  each `.claude/agents/*.md` frontmatter; `available` lists what HAIP actually
  serves (49 ids). Frontmatter parsing is first-`---`-block only and CRLF-tolerant,
  so a `model:` mention in the prose body cannot be picked up.
- **`run.sh engine {show|set|run}`** — Claude Code or OpenCode. State in
  `.loops/engine` (absent = claude, gitignored). `run` `exec`s the chosen engine.
- **Both wired into the top-level `case` and the bottom usage string.**
- **`.loops/verify.sh`** grew from 29 to ~122 lines: covers criteria 5-14 and
  18-19 mechanically, plus CRLF, exec-replacement, and curl-failure regressions.
- **`.loops/phase5-parallel.md`** — D3 evidence. Worktree paths, verbatim
  scope-check output both ways, `git rev-list --count origin/main..<branch>` = 0
  for both builders, and the integration mechanism named positively.
- **Landing fixes** (found while landing, outside the graded set, both
  mutation-tested): `lint` now accepts numbered criteria, not only checkboxes, so
  the template it enforces matches how contracts are actually written; and
  `score stall` no longer reports STALL on flat scores when the last verdict is
  PASS — a finished loop is not a stuck one.

## Gates, fired
- **scope-check** proved in both directions before being relied on: exit 0 on a
  clean builder worktree, exit 1 on a planted `.env.stolen`. Verbatim runs in
  `.loops/evidence/scope-check-negative.txt`.
- **Secret gate** held. The token value appears in no repo file, no fixture, no
  evidence file. Confirmed by literal-value scan each round, 0 hits.
- **Snapshot guard** intact across four rounds of run.sh edits.

## Findings — what this run actually taught
1. **`Agent(isolation: "worktree")` branches `origin/main`, not session HEAD**
   (`worktree.baseRef: fresh`). A worktree builder can *write* but cannot
   *behaviorally test* against uncommitted work. Roughly 15 of my dispatch prompts
   demanded exactly the shape isolation forbids. Verification-heavy builders now
   run in the main checkout. My defect, not the builder's.
2. **Builder self-reported mutation tables are worthless.** One listed three
   passing mutations — exactly the three it chose. I ran five; two returned exit 0
   where they had to fail. The orchestrator picks the mutations, always.
3. **Four builders claimed clean results that did not survive re-run.** Independent
   re-verification of every builder claim is now standard, not diligence.
4. **Completion notifications are unreliable.** Builder B finished at 15:15 with
   `end_turn` and no notification fired; it looked stalled for minutes. Hence
   `lib/agent-wait.sh`, which polls the transcript for `end_turn` plus a 15s quiet
   window. It takes a task-id, not a path.
5. **terra remains the strongest link** — one real defect per round for three
   rounds, each with a reproduction, then an honest convergence call instead of
   manufacturing a fourth. Never let the builder grade itself; this is why.

## Scope deviations, recorded not hidden
- A builder appended to `.loops/log.md`, outside its single-file allowlist.
- `lib/agent-wait.sh` is mine and was never in the contract's allowlist.

## Carried forward — real, not scheduled
1. The `~/.claude/hooks/pre-tool-use.sh` `rm -rf` guard is over-broad; it blocked
   `rm -rf /tmp/e2` and `rm -rf ~/.serena`. Cost ~4 minutes across this run.
2. `worktree check`'s hazard prefilter greps literal `/Users/|/home/`, so
   `/opt/homebrew/...` interpreter paths stay invisible.
3. explorer and planner tiers are still `PROPOSED-NOT-VERIFIED` — never proof-gated.
4. Consider `worktree.baseRef: head` so isolation and verification stop conflicting.
5. serena is deleted and gitignored; an MCP-registered builder call recreated
   `.serena/` once after removal.

## Next — Phase 6, repo hygiene
Every loop run leaves the repo filthy: 13 tracked scratch files this round. Plan:
1. `.loops/run/<phase>/` holds all per-run artifacts, gitignored. The durable set
   is exactly `contract.md`, `progress.md`, `log.md`, `feature_list.json`,
   `verify.sh`.
2. `run.sh tidy [--dry-run]` — list and delete debris, prune stale worktrees.
3. `lint` gains teeth: fail anything tracked outside the durable five.
4. Contract template gains a mandatory teardown criterion.
5. Migrate existing debris **last** — `verify.sh` currently asserts
   `.loops/pre-build-phase4/SHA256SUMS`, so moving files breaks the verifier first.
