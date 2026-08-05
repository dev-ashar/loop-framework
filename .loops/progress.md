# Progress

## Run: roster flip + HAIP routing + ADHD dedup + CLAUDE.md trim
Contract: `.loops/contract.md` (21 criteria, D1–D4, locked 2026-08-05)
Result: **PASS 1.00** at iteration 2 of max 10.

## Score trace
- iter 1 — BLOCK 0.81 (3 gaps)
- iter 2 — PASS 1.00 (21/21, independently verified)

## What landed
- **D1** ADHD ruleset no longer double-loads. `~/.claude/.i-have-adhd-always`
  deleted; both plugin hook copies emit 0 bytes; plugin stays enabled so
  `/i-have-adhd` still works on demand; plugin SKILL.md sha unchanged.
- **D2** `.loops/haip-config.md` — variable names only, redacted host, full model
  list, sol explicitly absent, tier mapping with cost lines, context window
  recorded as `unverified — assume capped at 200k`.
- **D3** CLAUDE.md 156 → 130 lines. Lines 99–130 (ADHD ruleset) byte-identical.
  explorer.md and planner.md now state their tool ceilings explicitly.
- **D4** Roster flipped, each on a proven tier: builder → `gpt-5.6-luna-mantle`,
  evaluator → `gpt-5.6-terra-mantle`, explorer stays `haiku`, opus orchestrates.

## Proof gates — both earned
- luna/builder: Read → Read → Edit → Bash, 4 tool_use/tool_result pairs matched
  by id, zero Write calls (Write excluded from --allowedTools), `canonicalModel`
  confirmed, /tmp scratch file edited in place.
- terra/evaluator: Read contract + Bash verify + parsable score + named gap.
- explorer: no dedicated proof run → row carries `PROPOSED-NOT-VERIFIED`. The
  luna-vs-haiku cost case ($0.20/$1.20 vs $1/$5) is open, not decided.

## Carried forward — real, not scheduled
1. `verify.sh`'s tool_use/tool_result gate only counts ≥1 of each; it does not
   assert the required tool *types* or Write-absence. Iteration 2's evaluator
   hand-verified those. Tighten before trusting the script alone.
2. `.loops/haip-probe-terra.log` has a literal shell separator line between its
   two JSON records — not valid JSONL. Cosmetic; fails no criterion.
3. Phase-3 leftover: `worktree check`'s hazard prefilter greps literal
   `/Users/|/home/`, so `/opt/homebrew/...` interpreter paths are invisible.
4. Phase-3 log line claims `scope-check` shipped. It does not exist in run.sh —
   it is Phase 4 criterion 34, unbuilt.

## Next
Phase 4 — parallel builders. Reconsider before building: native
`Agent(isolation: "worktree")` already provisions and cleans per-subagent
worktrees, so criteria 34–37's hand-rolled `merge-worktrees` is likely
redundant. `scope-check` is still worth building — it enforces the per-builder
file allowlist. That reconsideration is rule 8, not scope creep.

Nothing committed or pushed. 5 tracked files + 8 new `.loops/` artifacts in the
working tree, awaiting review.
