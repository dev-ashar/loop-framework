# LOOPS

A clean-slate, loop-native Claude Code setup. Built on one idea: **most agent
systems die from a weak harness, not a weak model.** So this kit keeps only what
the harness must still supply — role separation, a negotiated contract, and state
on disk — and delegates everything else to native loop primitives.

Grounded in Karpathy's *LOOPS.md: Field Notes on Agents That Run for Days*, the
Claude Code *Getting Started with Loops* guide, and the LOOPKIT layout.

## One loop, four rungs

There's only one loop — `gather → reason → act → verify`. What changes is how much
driving you hand off. Climb only as high as the task needs:

1. **Default (no command)** — the everyday posture. Do it in one pass, delegate the
   file-heavy work to an agent so your context stays clean, verify. You hand off *the check*.
2. **`/run-loop "<goal>"`** — hand off *the repetition*: negotiate a contract, then
   loop build→grade until it passes. Auto-triggers (with a heads-up) when a task
   turns out non-trivial.
3. **`/goal`** (native) — hand off *the stop condition* when one metric defines done.
4. **`/loop`, `/schedule`** (native) — hand off *the trigger* for recurring work.

You don't pick a tier up front. You just talk; the default handles small work and
climbs to `/run-loop` when the task earns it.

## Install

```bash
./install.sh --dry-run   # see exactly what it will do
./install.sh             # back up ~/.claude, then wire the kit in
```

Backup-first and idempotent. It symlinks agents/skills/hooks and the thin
`CLAUDE.md` into `~/.claude`, and **merges** `settings.json` (your plugins,
marketplaces, and rtk hook are preserved). Restore anytime from the printed
`~/.claude/backups/pre-loops-*` dir.

## The four roles (agents)

| Agent | Model | Job |
|---|---|---|
| `planner` | Sonnet | vague goal → contract + ordered plan; never writes code |
| `builder` | Sonnet | implements the plan; forbidden from grading itself |
| `evaluator` | Sonnet | adversarial — runs the app, grades vs contract, 0–1 + gap |
| `explorer` | Haiku | read-only find/map/trace |

The rule that makes it work: **the generator never grades its own output.**

## The loop spine (skills + native)

| Need | Reach for |
|---|---|
| A small task | *just ask* — the default delegates + verifies, no command |
| Run a whole task to done, autonomously | `/run-loop "<goal>"` |
| Agree on "done" before code | `/contract` → `.loops/contract.md` |
| Verify a change end-to-end | `/verify` |
| Score subjective quality | `/taste` |
| Measurable loop with a stop | native `/goal` |
| Recurring / scheduled work | native `/loop`, `/schedule` |
| Fan-out + adversarial verify | native `Workflow` |
| Second-agent review | native `/code-review` + `evaluator` |

Domain tracks: `data`, `debug`, `testing`, `llm-agent`.

## State on disk

Every run keeps its state in `.loops/` so it survives crashes and compaction —
recoverable from three files (Karpathy's test):

```bash
./run.sh init "make the ingestion pipeline idempotent"
./run.sh status
```

- `contract.md` — the graded boundary
- `progress.md` — current state
- `log.md` — append-only trace
- `feature_list.json` — the metric, for `/goal` runs

## A typical loop

The whole point: you invoke it **once**, not per turn.

```
/run-loop "make the ingestion pipeline idempotent"
```

1. It negotiates the contract — `builder` proposes testable criteria, `evaluator`
   attacks them on disk until airtight. **You approve once.**
2. Then it runs autonomously: `builder` implements → `evaluator` grades against the
   contract → the gap is fed back → repeat, until PASS / max-iterations / the
   contract proves wrong. State is written to `.loops/` every turn.
3. For a purely measurable goal, hand the locked contract to native `/goal`; for
   recurring work, `/loop` or `/schedule`.
4. Read `.loops/log.md` when judgment diverges. Let the loop restart if it goes sideways.

> A skill called each turn is *you* being the loop. `/run-loop` and `/goal` run the
> cycle themselves — that's the difference between a loop and a box of tools.

## Layout

```
.claude/  CLAUDE.md · settings.json · hooks/ · agents/ · skills/
templates/  contract.md · progress.md · log.md · feature_list.json
run.sh · install.sh · MEMORY.md · README.md
```
