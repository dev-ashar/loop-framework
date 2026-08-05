# Contract — Phase 4: parallel builders

Run: 2026-08-05 · branch `feat/phase1-foundations` · supersedes the D1–D4 roster
contract that passed 1.00 at commit `8af2690` (recoverable via
`git log -p -- .loops/contract.md`, archived at
`.loops/archive/contract-8af2690.md`). Criteria 5, 11, 12 are sourced near-verbatim
from the Phase 3/4 draft at `.loops/archive/contract-01d2954.md` (criteria 34, 36,
37) — do not re-litigate their wording without cause.

Criteria are numbered fresh 1–12. This is a new contract, not a continuation.

## Goal

Let the orchestrator run N `builder` agents concurrently on disjoint file sets
without collision. Today `run-loop` runs exactly one builder at a time, and that
is the constraint blocking a 10-agent setup.

Four deliverables:

- **P1 — Snapshot guard.** Prerequisite for the rest. This loop edits the harness
  that grades it, so committed-state copies of the files under mutation must exist
  before any build step, and the verify script must be complete before the
  evaluator first calls it.
- **P2 — `scope-check`.** A real `run.sh scope-check` enforcing a per-worktree file
  allowlist. Confirmed absent from `run.sh` today despite a Phase 3 log line
  claiming it shipped.
- **P3 — Merge protocol, right-sized.** `merge-worktrees` is **dropped**; replaced
  by a documented plain `git merge --no-ff` step the orchestrator runs directly.
- **P4 — Capability dispatch table.** A table mapping task-kind → agent → tool
  ceiling → model tier, so the orchestrator stops routing tasks to agents that
  structurally cannot perform them.

## Established facts (verified, do not re-litigate)

- `run.sh` has a `worktree` block at ~330–605 with `check`/`provision`/`fix`/`reap`.
  Neither `scope-check` nor `merge-worktrees` exists anywhere in it.
- `.claude/skills/run-loop/SKILL.md` is 77 lines and contains zero mentions of
  parallel, worktree, isolation, or scope-check. It documents a single-builder loop.
- `.claude/CLAUDE.md` is exactly **130** lines, the cap the prior contract imposed.
- Lines 99–130 of CLAUDE.md are the ADHD ruleset, required byte-identical. The
  reference copy is `.loops/pre-build-claudemd-99-130.txt`.
- Roster: `builder` → `gpt-5.6-luna-mantle`, `evaluator` → `gpt-5.6-terra-mantle`,
  `explorer` → `haiku` (no Bash), `planner` → `sonnet` (no Write). HAIP serves
  neither `gpt-5.6-sol` nor `claude-fable-5`.
- The prior run's evaluator proof invoked `.loops/verify.sh` before it existed and
  graded 0.45 on file-not-found. That is the exact defect P1 closes.
- Native `Agent(isolation: "worktree")` provisions and auto-removes a per-subagent
  git worktree. It does not merge work back — merging remains the orchestrator's job.
- `tests/run_tests.sh` is ~2086 lines, 33/37 passing. Not modified by this contract.

## Constraints

- Build may touch only: `run.sh`, `.claude/skills/run-loop/SKILL.md`,
  `.claude/CLAUDE.md`, `.claude/dispatch.md` (new), and `.loops/` state files.
- **Loop-state carve-out.** `.loops/` files are exempt from criterion 10's
  named-file restriction. The restriction binds fully outside `.loops/`.
- The ADHD ruleset block stays byte-identical to
  `.loops/pre-build-claudemd-99-130.txt`. **Anchor by content, not line number** —
  see criterion 3. Adding the dispatch-table link inside `## Routing` shifts every
  later line down by one, so any fixed `sed -n '99,130p'` assertion is invalid for
  this run and using one is itself a criterion failure.
- CLAUDE.md ends at **≤131 lines** — 130 plus exactly one link line. The dispatch
  table itself lives in `.claude/dispatch.md`, not inline.
- No criterion may adopt `gpt-5.6-sol` or `claude-fable-5`.
- No backward-compat shims. Remove obsolete paths outright.
- No modifying, running, or fixing `tests/run_tests.sh`.
- No push, deploy, publish, or PR.
- P1 is a hard prerequisite: no P2/P3/P4 work counts toward the score unless
  `.loops/pre-build-phase4/` and a complete `.loops/verify.sh` both exist first.
- Every criterion is mechanically checkable by shell, or explicitly marked
  evaluator-judgement. No vibes.

## Acceptance criteria

### P1 — snapshot guard (4)

1. `.loops/pre-build-phase4/` contains committed-state copies of `run.sh`, every
   `.claude/agents/*.md`, and `.claude/skills/run-loop/SKILL.md`, each taken via
   `git show HEAD:<path>` so they are immune to being read mid-edit. A
   `SHA256SUMS` manifest is present and `shasum -a 256 -c` passes against it.
2. `.loops/verify.sh` is complete — not a stub — before the evaluator's first
   invocation. Its first executable assertion after the shebang/`set` block must be
   a self-presence guard that exits non-zero with a message distinguishing
   "verify.sh missing" from a genuine build failure.
3. **Snapshot-anchored byte identity.** The ADHD block is verified by locating it
   via its heading anchor (`## Output style`) through end of that section and
   `diff`ing that span against `.loops/pre-build-claudemd-99-130.txt`. Any check
   that hardcodes line numbers 99–130 FAILS this criterion, because the link line
   added in `## Routing` shifts the span. Evaluator judgement.
4. `.loops/pre-build-phase4/` is treated read-only after creation: nothing in the
   build rewrites it, and `git diff --name-only` shows no modification to files
   under it after their initial add.

### P2 — `scope-check` (1 criterion, 4 required fixtures)

5. `run.sh scope-check <worktree-path> <base-ref> <allowed-file-list>` exits 0 iff
   the worktree's **full divergence from `<base-ref>`** is a subset of the allowed
   list, else exits 1 naming the offending path(s) on stdout. The path set is the
   union of committed and uncommitted change:
   `git -C <path> diff --name-only "$(git -C <path> merge-base <base-ref> HEAD)"`
   plus `git -C <path> ls-files --others --exclude-standard`. A bare
   `git diff --name-only` is explicitly insufficient and FAILS this criterion: by
   the time the merge step runs, a parallel builder's work is committed and the
   working tree is clean, so a working-tree-only diff is empty and the guard is a
   no-op exactly when it matters. All four fixtures required, each in its own tmp
   repo + worktree: (a) in-scope **committed** edit → exit 0; (b) out-of-scope
   **committed** edit → exit 1 naming the path; (c) out-of-scope **uncommitted**
   edit → exit 1 naming it; (d) out-of-scope **new untracked** file → exit 1
   naming it.

### P3 — merge protocol (2) — decision: DROP `merge-worktrees`

Locked reasoning: the specified subcommand (sequential `git merge --no-ff`, stop at
first conflict, no auto-abort) is ~15–20 lines of bash that adds no capability the
orchestrator lacks — it drives Bash directly and can run two commands per branch.
Native `Agent(isolation: "worktree")` already handles provisioning and cleanup. Per
rule 8, wrapping the merge too would be harness for its own sake.

6. `run.sh` contains no `merge-worktrees` subcommand. Check:
   `! grep -q 'merge-worktrees' run.sh`.
7. The merge step is documented instead: `git merge --no-ff` appears inside the
   `### Parallel builders` span of `.claude/skills/run-loop/SKILL.md`, within 3
   lines of the `scope-check` mention, and the span states in prose that the merge
   stops at the first conflict with the conflicting branch named and no auto-abort.

### P4 — capability dispatch table (3)

8. `.claude/dispatch.md` exists and lists, for each of `explorer`, `planner`,
   `builder`, `evaluator`, and the orchestrator: its current model tier (`haiku`,
   `sonnet`, `gpt-5.6-luna-mantle`, `gpt-5.6-terra-mantle`, `opus-5`) and its tool
   ceiling (`Read/Grep/Glob only`, `Read/Grep/Glob only`, full, full, full).
9. `.claude/dispatch.md` states the task-kind routing — recon/mapping → `explorer`;
   contract drafting → `planner`; code edits → `builder`; grading → `evaluator` —
   and explicitly names the two known-broken routes: that a Bash- or
   Write-requiring task must not be dispatched to `explorer` or `planner`, naming
   both agents and both missing tools. Must pass an anti-negation guard: the
   sentence asserts a routing rule rather than merely negating one. Evaluator
   judgement.
10. `.claude/CLAUDE.md` is ≤131 lines, gains exactly one line linking to
    `.claude/dispatch.md` from within its `## Routing` section, and still contains
    all five headings: `## The loop`, `## The nine rules`, `## Routing`, an Output
    style heading, an Engineering principles heading. `git diff --name-only` touches
    nothing outside the Constraints list (`.loops/` exempt).

### Parallel-builders documentation (2)

11. `.claude/skills/run-loop/SKILL.md` contains a `### Parallel builders` section
    stating that when the locked plan has ≥2 builder steps over disjoint file sets,
    the orchestrator provisions one worktree per step, dispatches that many
    `builder` agents in a single message, runs `scope-check` per worktree, and
    merges via `git merge --no-ff` before the evaluator grades. Check: extract the
    span from `### Parallel builders` to the next `##`/`###` heading; assert
    `worktree`, `scope-check`, and `git merge --no-ff` all appear inside it.
12. **Fast-path guard.** The single-builder path is documented as ceremony-free:
    with exactly one builder step, no worktree is provisioned and `builder` is
    dispatched in place exactly as today. The guard sentence appears inside the
    `### Parallel builders` span or within 3 lines after it, and passes the
    anti-negation guard with one exception — the tokens `not`, `no`, `skip` are
    permitted in the phrase describing what is *omitted for the single-builder
    case* (e.g. "no worktree is provisioned"). The guard is applied to a ±2-line
    window with that phrase masked out. Any negation attaching to the parallel
    protocol itself FAILS.

## Verify command

`bash .loops/verify.sh`, which must exist complete per criterion 2 before the
evaluator runs it. The builder writes it; skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /Users/devashar/Documents/DS/workspace/loops
test -f .loops/verify.sh || { echo "verify.sh missing — contract defect, not build fail" >&2; exit 1; }

# P1
test -d .loops/pre-build-phase4
test -s .loops/pre-build-phase4/SHA256SUMS
( cd .loops/pre-build-phase4 && shasum -a 256 -c SHA256SUMS --status )
# ADHD block by content anchor, NOT line numbers (criterion 3)
awk '/^## Output style/,0' .claude/CLAUDE.md | head -32 > /tmp/adhd-now.txt
diff -q .loops/pre-build-claudemd-99-130.txt /tmp/adhd-now.txt

# P2 — four fixtures, builder wires up tmp repos + worktrees
#   (a) in-scope committed -> 0  (b) out-of-scope committed -> 1
#   (c) out-of-scope uncommitted -> 1  (d) out-of-scope untracked -> 1

# P3
! grep -q 'merge-worktrees' run.sh
grep -q 'git merge --no-ff' .claude/skills/run-loop/SKILL.md

# P4
test -s .claude/dispatch.md
for tok in explorer planner builder evaluator \
           "gpt-5.6-luna-mantle" "gpt-5.6-terra-mantle" haiku sonnet; do
  grep -q "$tok" .claude/dispatch.md
done
grep -q 'dispatch.md' .claude/CLAUDE.md
[ "$(wc -l < .claude/CLAUDE.md)" -le 131 ]
! grep -rq 'gpt-5.6-sol\|claude-fable-5' .claude/

# Parallel builders doc
grep -q '### Parallel builders' .claude/skills/run-loop/SKILL.md

echo EVALUATOR-JUDGEMENT-REQUIRED: 3 9 12
echo VERIFY_OK
```

Criteria requiring evaluator judgement rather than the script: 3, 9, 12.

## Out of scope

- Building `merge-worktrees` (decided: dropped, P3).
- Archived criterion 38 — staging-safety gate on `worktree fix` / `provision --pr`.
  Real and unbuilt; deferred.
- The `worktree check` hazard-prefilter gap: it greps literal `/Users/|/home/`, so
  `/opt/homebrew/...` interpreter paths are invisible to it.
- `.loops/haip-probe-terra.log`'s non-JSONL separator line (cosmetic).
- A dedicated explorer proof run to clear its `PROPOSED-NOT-VERIFIED` status.
- Running, fixing, or modifying `tests/run_tests.sh`.
- A live end-to-end 10-agent run across real repos. This contract builds and
  documents the gates; exercising them is the follow-up.
- Any push, deploy, or publish.

## Resolved decisions (contract LOCKED 2026-08-05)

- **Dispatch table → `.claude/dispatch.md`**, linked from `## Routing`. CLAUDE.md
  stays at ≤131 (one link line). Human decision: keep the most-read file thin.
- **Merge protocol → drop `merge-worktrees`**, replaced by a documented plain
  `git merge --no-ff` the orchestrator runs. Planner's recommendation, accepted.
- **Byte identity → content-anchored, not line-anchored.** The link line inside
  `## Routing` shifts all later lines by one, so `sed -n '99,130p'` would silently
  compare the wrong span. Criterion 3 forbids line-number anchoring outright. This
  is an orchestrator amendment to the planner's draft, which had assumed all new
  content would be appended after line 130.
- **Snapshot retention → keep `.loops/pre-build-phase4/`** as an audit trail. It is
  a few KB. Future phases add their own `pre-build-phaseN/`.
- **Worktree cleanup → auto-delete after a successful merge**, with
  `run.sh worktree reap --prune` as the fallback for orphans.
- **Numbering → fresh 1–12.**
