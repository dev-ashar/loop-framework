# Contract

Run: 2026-08-05 · branch `feat/phase1-foundations` · prior contract archived at
`.loops/archive/contract-01d2954.md`

## Goal

Three deliverables:

- **D1** — Stop the ADHD ruleset from loading twice per session. CLAUDE.md is the
  single source of truth; the plugin's always-on SessionStart injection goes away.
- **D2** — Document and prove out GPT-5.6 access through the already-configured
  HAIP gateway. No proxy, no install: `ANTHROPIC_BASE_URL` /
  `ANTHROPIC_AUTH_TOKEN` are already exported from `~/.zshenv`.
- **D3** — Audit CLAUDE.md against its own rule 8 (delete the harness), and fix
  the agent-tooling gaps found during this run.

## Established facts (verified, do not re-litigate)

- `/Users/devashar/.claude/CLAUDE.md` is a **symlink** to
  `loops/.claude/CLAUDE.md`. The repo file is the global instruction file.
- The ADHD ruleset loads twice: CLAUDE.md lines 99–156 (user's tuned ~35-line
  version), and the plugin SessionStart hook gated on
  `~/.claude/.i-have-adhd-always`, which emits the full 6848-byte SKILL.md body.
- A real completion **succeeds** against `gpt-5.6-terra-mantle` through HAIP on
  both `/v1/messages` (Anthropic shape) and `/v1/chat/completions` (OpenAI
  shape). Returned text `ok`.
- HAIP serves: `gpt-5.6-terra-mantle`, `gpt-5.6-luna-mantle`, gpt-5.5(-mantle,
  -nano), gpt-5.4(-mantle, -nano), gpt-5-mini; claude-opus-5, claude-opus-4-8,
  claude-opus-4-7, claude-opus-4-6, claude-sonnet-5, claude-haiku-4-5; Gemini
  3.x flash and flash-lite.
- HAIP does **not** serve `gpt-5.6-sol`. It does **not** serve `claude-fable-5`.
- Costs per 1M in/out: Luna $0.20/$1.20 · Terra $2/$12 · Sol $5/$30 ·
  Haiku 4.5 $1/$5. Luna is cheaper than Haiku.
- `agents/explorer.md` and `agents/planner.md` both declare
  `tools: Read, Grep, Glob` — no Bash, no Write. Recon and file-authoring tasks
  dispatched to them fail silently.

## Constraints

- D1 touches only: delete `/Users/devashar/.claude/.i-have-adhd-always`.
- D2 writes documentation and log artifacts only. It must never write the value
  of `ANTHROPIC_BASE_URL` or `ANTHROPIC_AUTH_TOKEN` into any repo file. No
  proxy, no new env file, no install step.
- D3 touches only `.claude/CLAUDE.md`, `.claude/agents/explorer.md`, and
  `.claude/agents/planner.md`.
- D4 touches only `.claude/agents/builder.md`, `.claude/agents/evaluator.md`,
  `.claude/agents/explorer.md`, and `.loops/haip-config.md`. It may write
  `.loops/haip-<role>-observed.log` artifacts.
- D4 may not change any agent's `model:` field unless that tier passed its
  observed tool-using run. A failed or unrun proof leaves the field untouched.
- CLAUDE.md lines 99–130 (the ADHD ruleset wording) stay byte-identical.
- No criterion may adopt `gpt-5.6-sol` as available, or treat "top tier" as
  decided.
- No criterion may mark a GPT-tier role reassignment done without an observed
  tool-using run.
- No backward-compat shims (CLAUDE.md engineering principles). Remove obsolete
  paths outright.
- All edits to CLAUDE.md must be reviewable as a `git diff`.
- **Loop-state carve-out (amended iteration 1).** Criterion 15 scopes *build
  product* only. `.loops/` harness-state files — `contract.md`, `log.md`,
  `progress.md`, `feature_list.json`, `verify.sh`, `pre-build-*`, and the
  `haip-*` artifacts the contract itself mandates — are exempt from the
  named-file restriction. Reason: the contract simultaneously required
  `.loops/verify.sh` to be created and forbade files outside the D1–D4 list,
  and the orchestrator's own lock-time amendment necessarily edited
  `contract.md`. That is a defect in the contract's drafting, not in the build.
  The restriction still binds fully outside `.loops/`.

## Acceptance criteria

### D1 — stop double-injection (5)

1. `test ! -e /Users/devashar/.claude/.i-have-adhd-always`
2. Both hook copies (`plugins/cache/...` and `plugins/marketplaces/...`), run
   directly with the flag absent, exit 0 and print 0 bytes.
3. `jq -e '.enabledPlugins["i-have-adhd@i-have-adhd"] == true'` on
   `~/.claude/settings.json` — plugin stays installed so `/i-have-adhd` still
   works on demand.
4. `skills/i-have-adhd/SKILL.md` unmodified (sha256 matches pre-build snapshot),
   `disable-model-invocation: true` intact.
5. CLAUDE.md lines 99–130 byte-identical to pre-build snapshot.

### D2 — HAIP-backed GPT-5.6 access (6)

6. `.loops/haip-config.md` documents variable **names** (`ANTHROPIC_BASE_URL`,
   `ANTHROPIC_AUTH_TOKEN`, sourced from `~/.zshenv`), a redacted host, and the
   full confirmed model list. States explicitly that `gpt-5.6-sol` is NOT
   served. Check: grep for each required token string.
7. Hard secret gate: `grep -rF "$ANTHROPIC_AUTH_TOKEN"` across the repo returns
   0 hits; `git diff` contains no token-shaped secret line.
8. `.loops/haip-probe-terra.log` and `.loops/haip-probe-luna.log` exist, each
   from an actually-executed call, non-empty, containing a non-error response
   body. Terra probed on both API shapes.
9. `## Tier mapping` section: luna and terra each mapped to a candidate role
   with its cost line; an explicit "Opus remains orchestrator" sentence; no
   reference to sol as available.
10. **Risk-1 gate.** Any role reassignment in criterion 9 has a matching
    `.loops/haip-<role>-observed.log` showing that agent, under the GPT tier,
    invoking its declared tools and completing the designated proof task
    (defined in D4, criterion 18) — distinct from the bare completion probe in 8.
    Missing this, the mapping entry must carry the literal marker
    `PROPOSED-NOT-VERIFIED`.
11. **Risk-2 gate.** `## Context window` section states either an executed,
    observed effective limit for a non-Anthropic model through HAIP, or the
    literal string `unverified — assume capped at 200k`.

### D3 — trim CLAUDE.md + agent-tooling fix (6)

12. `wc -l .claude/CLAUDE.md` is **≤ 130** (from 156). Every heading in
    criterion 13 must survive the trim.
13. These headings survive: `## The loop`, `## The nine rules`, `## Routing`,
    an `Output style` heading, an `Engineering principles` heading.
14. CLAUDE.md lines 99–130 byte-identical to pre-build snapshot.
15. `git diff --name-only` touches only the files named in Constraints.
16. `agents/explorer.md` gains `Bash` in its `tools:` frontmatter, OR its body
    gains an explicit sentence stating it cannot inspect binaries, run CLIs, or
    verify installed-tool behaviour, and that such recon goes elsewhere.
    `agents/planner.md` likewise gains `Write` or an explicit statement that it
    cannot persist files and must return content to the orchestrator.
17. Regression guard: `! grep -rq claude-fable-5 .claude/` — nothing may
    reference a model HAIP does not serve.

### D4 — roster flip, proof-gated (4)

Target roster: **opus-5 orchestrates** (this session, never delegated) ·
**terra critiques** (evaluator) · **luna writes all code** (builder) ·
**haiku finds** (explorer). Each non-orchestrator reassignment is gated on its
own observed run.

18. **Proof task, defined.** For each candidate tier a real subagent run is
    executed and captured to `.loops/haip-<role>-observed.log`. The run is only
    a pass if the log shows the agent *invoking its declared tools*, not merely
    emitting text:
    - `builder`/luna — must Read an existing repo file, make one scoped Edit to
      a scratch file under `/tmp`, run one Bash command, and report the result.
      Log must evidence all three tool types.
    - `evaluator`/terra — must Read the contract, run the verify script via
      Bash, and return a numeric 0–1 score with at least one named gap. Log
      must evidence Read + Bash + a parsable score.
    A log containing only assistant prose, or a refusal, or a tool call with no
    result, is a FAIL for that tier.
19. `agents/builder.md` sets `model: gpt-5.6-luna-mantle` **iff** criterion 18's
    builder proof passed. Otherwise the file's `model:` is unchanged and
    `haip-config.md`'s mapping row carries `PROPOSED-NOT-VERIFIED`.
20. `agents/evaluator.md` sets `model: gpt-5.6-terra-mantle` **iff** criterion
    18's evaluator proof passed. Same fallback rule as 19.
21. `agents/explorer.md` keeps an explicitly stated model tier and, per
    criterion 16, either gains `Bash` or states it cannot do CLI recon. The
    luna-vs-haiku cost note ($0.20/$1.20 vs $1/$5) is recorded in
    `haip-config.md` as a decision with a stated reason either way.

## Verify command

`bash .loops/verify.sh` — created by the builder, containing:

```bash
set -euo pipefail
cd /Users/devashar/Documents/DS/workspace/loops

# D1
test ! -e "$HOME/.claude/.i-have-adhd-always"
for h in "$HOME/.claude/plugins/cache/i-have-adhd/i-have-adhd/0.1.0/hooks/always-on.sh" \
         "$HOME/.claude/plugins/marketplaces/i-have-adhd/hooks/always-on.sh"; do
  [ -f "$h" ] || continue
  out=$(sh "$h"); [ -z "$out" ]
done
jq -e '.enabledPlugins["i-have-adhd@i-have-adhd"] == true' "$HOME/.claude/settings.json" >/dev/null

# D2
test -s .loops/haip-config.md
for tok in gpt-5.6-terra-mantle gpt-5.6-luna-mantle gpt-5.6-sol \
           '## Tier mapping' '## Context window'; do
  grep -q "$tok" .loops/haip-config.md
done
test -s .loops/haip-probe-terra.log
test -s .loops/haip-probe-luna.log
if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  ! grep -rqF "$ANTHROPIC_AUTH_TOKEN" . 2>/dev/null
fi

# D3
! grep -rq claude-fable-5 .claude/
for h in '## The loop' '## The nine rules' '## Routing' 'Output style' 'Engineering principles'; do
  grep -q "$h" .claude/CLAUDE.md
done
grep -qE 'Bash|cannot inspect binaries' .claude/agents/explorer.md
grep -qE 'Write|cannot persist files' .claude/agents/planner.md
wc -l .claude/CLAUDE.md

echo VERIFY_OK
```

Criteria requiring evaluator judgement rather than the script: 4, 5, 10, 14, 15.

## Out of scope

- Patching the i-have-adhd plugin upstream or opening a PR.
- Any proxy that routes an Anthropic subscription OAuth token (violates
  Anthropic consumer terms).
- Requesting that platform add `gpt-5.6-sol` to HAIP (surfaced as a follow-up).
- Pushing, deploying, or publishing anything.

## Resolved decisions (contract LOCKED 2026-08-05)

- **Q1 → ≤130 lines**, all criterion-13 headings surviving. Criterion 12.
- **Q2 → proof task defined in criterion 18**, per-role, tool-invocation
  evidenced in the log. Prose-only logs fail.
- **Q3 → Terra accepted** as the top GPT tier available. Sol is recorded as a
  platform follow-up, not a blocker. This run proceeds.

Amendment note: D4 (criteria 18–21) added at lock time to cover the requested
roster flip — opus orchestrates, terra critiques, luna codes, haiku explores.
The Risk-1 gate already in criterion 10 governs it; D4 makes the per-role
outcome explicit rather than leaving it to prose.

Known redundancy, deliberately kept: criteria 5 and 14 assert the same
byte-identity on CLAUDE.md lines 99–130. Kept because they gate different
deliverables (D1's hook removal vs D3's trim) and either could break it
independently. Collapse only if a future run merges D1 and D3.
