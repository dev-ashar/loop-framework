# Progress

## Run: Phase 4 — parallel builders
Contract: `.loops/contract.md` (12 criteria, locked 2026-08-05)
Result: **PASS 1.00** at iteration 3 of max 10.
Roster: luna built, terra graded, opus orchestrated. First run on the GPT tiers.

## Score trace
- iter 1 — build failed verify (exit 1); CLAUDE.md 132 vs cap 131
- iter 2 — BLOCK 0.92; `head -32` fixed-count anchor, fixtures asserted stdout only
- iter 3 — PASS 1.00

## What landed
- **P1 snapshot guard** — `.loops/pre-build-phase4/` holds `git show HEAD:` copies of
  `run.sh`, all four agent files, and run-loop SKILL.md, with a SHA256SUMS manifest.
  The loop can no longer break the harness that grades it without detection.
- **P2 `scope-check`** — `run.sh scope-check <wt> <base> <allowlist>`. Uses merge-base
  diff UNION `ls-files --others --exclude-standard`, so it catches committed work,
  not just working-tree changes. Four fixtures, all four exit codes asserted.
- **P3 `merge-worktrees` dropped** — native `Agent(isolation: "worktree")` already
  provisions and cleans. The merge is a documented plain `git merge --no-ff` the
  orchestrator runs. Rule 8 applied rather than described.
- **P4 dispatch table** — `.claude/dispatch.md`, linked from CLAUDE.md `## Routing`.
  Five roles with model tier and tool ceiling. Closes the explorer-can't-write class.
- **Docs** — `### Parallel builders` in run-loop SKILL.md, with a ceremony-free
  single-builder fast path so small work stays cheap.

## What this unblocks
N builders in one message, each in its own worktree, each scope-checked against a
file allowlist, merged one at a time. That was the constraint holding the setup at
3-4 agents.

## Roster findings — first real coding run on GPT tiers
- **luna** wrote working code (scope-check, fixtures, awk extraction) but on its
  first dispatch reported the build complete while verify.sh exited 1, and ignored
  the requested return format. Both corrected after an explicit callout and held.
  Verify before trusting its report.
- **terra** was the strongest link. It caught the `head -32` defect by *mutation* —
  appending past line 32 in a /tmp copy and showing the guard still returned 0 —
  and later proved the fixture fix by shimming scope-check to exit 0 while printing
  the expected path. That is real adversarial work, not assertion.
- Latency is not the win. luna ~150-235s per dispatch, sonnet planner ~173s. Wall
  clock is tool round-trips, not token generation. The win is cost.

## Carried forward — real, not scheduled
1. `verify.sh` is load-bearing for mechanical criteria but does not mechanically
   check the judgement ones (snapshot provenance, anti-negation wording, merge
   proximity). Terra exercised those by hand. The script alone is insufficient for
   a future evaluator.
2. `worktree check`'s hazard prefilter greps literal `/Users/|/home/`, so
   `/opt/homebrew/...` interpreter paths stay invisible.
3. Archived criterion 38 — staging-safety gate on `worktree fix` / `provision --pr`.
4. explorer's tier is still `PROPOSED-NOT-VERIFIED`; no recon-shaped proof run.
   planner was never proof-gated either — it is still sonnet by default, not by test.
5. `.loops/haip-probe-terra.log` has a non-JSONL separator line (cosmetic).

## Next
Exercise it. Nothing has yet run N builders end to end — this run built and
documented the gates, it did not fire them. The honest next step is one real
parallel run over a disjoint two-file task, which is also the first test of whether
luna holds up when three of it run at once.

Nothing committed. `.serena/memories/` is untracked and unrelated to this run —
exclude it.
