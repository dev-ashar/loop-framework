# Forensic findings — LOOPS harness, gathered 2026-07-29

Evidence base: 7 repos with live `.loops/` state, plus the harness source at
`/Users/devashar/Documents/DS/workspace/loops`. Gathered by 3 explorer agents +
direct tooling probe. This file is the input to the contract; it is evidence,
not a plan.

## A. Verified tooling facts

- git 2.50.1 (Apple Git-155) — full worktree support.
- gh 2.76.1, authenticated `dev-ashar` via keyring, scopes `admin:public_key, gist, read:org, repo`.
  → `repo` scope present, so automated PR creation is viable.
- arthur has NO submodules (`git submodule status` empty). An earlier survey claim
  of a `deps/serena` submodule was wrong; do not design for it.

## B. Per-repo state snapshot (2026-07-29)

| repo | worktrees | dirty files | .running |
|---|---|---|---|
| data-catalog | 1 | 4 | **STALE since 07-25** |
| data-solutions-kujata | 1 | 1 | – |
| plugins/runbooks | 2 | 0 | – |
| workspace/features | 0 | 0 | – |
| workspace/loops | 1 | 2 | active (this run) |
| arthur2.0/petrichor | 2 | 28 | – |
| arthur2.0/arthur | **6** | 4 | – |

Worktree sprawl is real and unmanaged: 12 worktrees across the set, nothing reaps them.

## C. Confirmed failure modes, ranked by evidence strength

### C1. No learning substrate at all — the strongest finding
- `MEMORY.md` at the harness root is **pure boilerplate, zero entries**. No `memory/`
  dir exists.
- No agent definition reads past failures. builder/evaluator/planner/explorer all
  start cold every run.
- Consequence, observed twice as the *same class* of mistake:
  - data-catalog (polymarket PnL): discovered mid-build that
    "API cashPnl is net-of-fees; our profit_loss_asset is gross (fees in separate
    fees_asset col)" — external API semantics assumed, not verified up front.
  - arthur (hyperunit bridge): discovered mid-build that the Unit API's HL-side
    quantities are always NULL and not enrichable on-chain; deposit logic had to be
    redesigned. Log: "Deposit grain (per treasury output) != Unit op; reused
    protocolAddress + treasury change inflate amount."
- Root cause: contracts do not require *validating external data-source semantics
  before* acceptance criteria are locked, and nothing records the lesson afterward.

### C2. Contract quality drift — verify command has no fixed location
- 3/7 repos: acceptance criteria drift from numbered/testable into prose.
  - data-catalog criteria 1–5 tight; 6–7 vague ("reconciliation table + residuals
    are recorded" — no format spec; "validated by an ad-hoc read-only SELECT" — which?).
  - petrichor contract names no titled Verify section; the command
    (`pytest tests/common -q`) is trailing prose.
  - arthur contract references "crit2,3,6,7" but criteria numbering is implicit.
- Nothing lints a contract before it locks.

### C3. Harness bypass — state files simply absent
- data-solutions-kujata ran real loop work (multichain autoheal, 2 adversarial
  rounds, deployed to prod) with **no contract.md and no progress.md** — tracked
  inline in log.md only. The 3-file recoverability guarantee silently did not hold.

### C4. No score persistence, no stall detection
- `templates/feature_list.json` has `iterations.max` (10) and `spent`, but
  `metric.baseline/best/target` stay `null` in every repo and there is **no per-
  iteration score field**. The evaluator's 0–1 grade is never written to disk.
- Therefore the documented "score regressed or stuck flat for 2 rounds → restart"
  rule in run-loop is **unenforceable** — the data to detect it does not exist.
- `run.sh` has only `init` and `status`. No score recording, no stall check, no
  stale-state reaping, no multi-repo view.

### C5. Stale `.running` markers are never reaped
- data-catalog `.running` has sat since 2026-07-25 (4 days) at PASS 1.00 awaiting
  landing approval. `stop.sh` clears the marker on clean stop only; a crashed or
  abandoned run leaves it forever, and nothing reports it.

### C6. Log format drift (minor)
- plugins/runbooks and workspace/features maintain `## [YYYY-MM-DD HH:MM] op | title`
  perfectly (554-line log, pristine).
- data-catalog mixes `## [2026-07-25 20:35]` with `## [2026-07-25]` (time dropped),
  which breaks any parser.

### C7. Concurrency is architecturally serial
- run-loop dispatches exactly one builder, then one evaluator, and the orchestrator
  blocks on each return before dispatching the next.
- `builder.md:18` already says "unless dispatched into a worktree for parallel
  isolation" and `planner.md:23` says plans should be "scoped to a disjoint set of
  files where possible so builders can run in parallel" — **both designed, neither wired.**
- Hard blockers to more agents: (a) no worktree provisioning, so parallel builders
  would collide in one tree; (b) no merge/aggregation strategy for N builder diffs;
  (c) no per-agent scoping enforcement.
- Note: worktrees are a prerequisite for safe parallel building. Order matters.

## D. Worktree hazards, ranked by what actually breaks

1. **Hardcoded absolute paths in git hooks — hard blocker.**
   `arthur/.git/hooks/pre-commit:6` → `INSTALL_PYTHON=/Users/devashar/Documents/DS/arthur2.0/arthur/env/bin/python3.12`,
   and `core.hooksPath` is the absolute `.../arthur/.git/hooks`. Every commit from a
   fresh worktree fails until remediated.
2. **Gitignored-but-present files** — absent in a fresh worktree, fail silently:
   - `data-catalog/databricks/transpose_prod_catalog/.env`
   - `plugins/runbooks/.env.local`
   - `.terraform/` in data-catalog and infrastructure
   - `node_modules/` in runbooks (bun, not npm)
   - `env/` `venv/` in arthur, petrichor
3. **Bootstrap cost per repo**: arthur highest (~5 min: venv + `pip install -e .` +
   `pre-commit install` + hook fix); runbooks `bun install` (~2 min); terraform repos
   `terraform init`; petrichor/kujata venv (~1 min); loops none.
4. **Dirty trees block worktree workflows**: petrichor has 28 uncommitted files.

## E. What works and must not be broken

- **Adversarial evaluator genuinely works.** `evaluator.md` opens with "the work is
  broken, prove it" and it demonstrably catches real gaps: runbooks Track A 0.45→1.00,
  arthur hyperunit iter1 graded BLOCK 0.62 with a specific cause ("ETH filter has only
  2 Base addrs (no-op on ETH) → 6+ fixed-dust senders unfiltered").
- **Live empirical validation before landing.** data-catalog checked the fix against
  the live API to the cent (broken −201.45 → corrected −819.30 → API −819.30 exact);
  arthur cross-checked 49 rows against mempool.space.
- **Land-on-PASS, gate deploy separately.** The `.running`-at-PASS state in
  data-catalog is the human gate working as designed, NOT a defect. Do not
  "fix" it by auto-landing.
- **Fast micro-loops.** transpose_prod_catalog ran 6+ tasks 07-16→07-22, mostly
  PASS at iter1–2. The harness is not slow; do not add ceremony to the fast path.
