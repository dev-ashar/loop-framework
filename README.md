# LOOPS

A clean-slate, loop-native Claude Code setup. Built on one idea: **most agent
systems die from a weak harness, not a weak model.** So this kit keeps only what
the harness must still supply — role separation, a negotiated contract, and state
on disk — and delegates everything else to native loop primitives.

Grounded in Karpathy's *LOOPS.md: Field Notes on Agents That Run for Days*, the
Claude Code *Getting Started with Loops* guide, and the LOOPKIT layout.

> **If you are an agent working in this repo, read [Rules for agents](#rules-for-agents)
> first.** It is the part of this file that changes what you do.

## Quickstart

```bash
./install.sh          # wires ~/.claude and puts `loops` on your PATH
loops                 # interactive config
```

Bare `loops` opens a picker over the roster and the engine:

```
configure> ▊
  Select a role or engine
> builder         gpt-5.6-luna-mantle
  evaluator       gpt-5.6-terra-mantle
  explorer        haiku
  general-purpose gpt-5.6-terra-mantle
  planner         sonnet
  engine          claude (/opt/homebrew/bin/claude)
```

Pick a role → pick from the models the gateway actually serves → confirm:

```
builder: gpt-5.6-luna-mantle -> sonnet
Apply change? [y/N] y
```

Then start a loop from inside Claude Code — that's the daily interface, not the CLI:

```
/run-loop "make the ingestion pipeline idempotent"
```

Full command surface: [The `loops` CLI](#the-loops-cli).

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
./install.sh --dry-run   # see exactly what it will do; writes nothing
./install.sh             # back up ~/.claude, then wire the kit in
```

Backup-first and idempotent. Eight steps: back up `~/.claude`, symlink
agents / skills / hooks, install the thin `CLAUDE.md`, **merge** `settings.json`
(your plugins, marketplaces, and rtk hook are preserved), create the global lesson
store, and symlink `run.sh` to `~/.local/bin/loops`. Restore anytime from the
printed `~/.claude/backups/pre-loops-*` dir.

Everything is symlinked, so **this repo is the single source of truth** — editing
an agent here changes it everywhere, and `~/.claude` never diverges.

Two things the installer does not do for you:

- `~/.local/bin` must be on `PATH` (it prints a warning if it isn't). Put the
  export in `~/.zshenv`, not `~/.zshrc`, or non-interactive shells won't see it.
- `fzf` is only needed for the interactive picker (`brew install fzf`). Every
  command has a non-interactive equivalent, so the kit works without it.

## The roles (agents)

| Agent | Model | Job |
|---|---|---|
| *orchestrator* | Opus (this session) | plan, judge, route, synthesize, decide — inline, never a subagent |
| `planner` | `sonnet` | vague goal → contract + ordered plan; never writes code |
| `builder` | `gpt-5.6-luna-mantle` | implements the plan; forbidden from grading itself |
| `evaluator` | `gpt-5.6-terra-mantle` | adversarial — runs the thing, grades vs contract, 0–1 + gap |
| `explorer` | `haiku` | read-only find/map/trace; no Bash |
| `general-purpose` | `gpt-5.6-terra-mantle` | catch-all when no named role fits; all tools |

`loops models list` prints the live roster; it reads the `model:` frontmatter key
in `.claude/agents/*.md`, which is the only place these are configured.

Two rules make it work: **the generator never grades its own output**, and **Opus
only orchestrates** — the Opus-tier thinking happens inline in your session; every
subagent runs at the cheapest competent tier. Delegate volume, not judgment.

## The `loops` CLI

Bare `loops` opens an fzf picker over the roster and the engine row: pick a role,
pick from what the gateway actually serves, confirm with `y`, and the choice is
written to that agent's frontmatter.

```
loops                                  # interactive config (needs a TTY + fzf)
loops init ["goal"]                    # create .loops/ from templates, seed the goal
loops status                           # contract + progress + tail of log
loops lint [path]                      # check contract structure; silent = clean
loops log "<op>" "<title>"             # append one line to .loops/log.md
loops score record <iter> <score> <verdict>
loops score stall                      # exit 2 = score flat/regressing → restart
loops reap                             # report a stale .running marker (>48h)
loops multireport <repo-path>...       # loop state across several repos
loops lesson record|check <text>       # global cross-repo lesson store
loops models list|available|set <role> <model>
loops engine show|set|run              # claude or opencode; state in .loops/engine
loops scope-check <worktree> <base-ref> <allowed-files>
loops worktree check|provision|fix|reap
```

Conventions worth knowing before you script against it:

- **Silence means clean.** `lint`, `reap`, and a passing `score stall` print
  nothing and exit 0. Absence of output is a pass, not a no-op.
- **Exit codes carry meaning.** `score stall` exits 2 specifically for a stall;
  a missing subcommand exits 1 with usage.
- **Most commands are CWD-relative** — they act on `./.loops/`. `models` and
  `engine` resolve their data through the installed script's real location, so
  they work from any directory.
- **No TTY or no fzf** makes bare `loops` print the non-interactive equivalent and
  exit 1 rather than hanging. `LOOPS_FZF` points at an fzf that isn't on `PATH`.

Lessons live in `~/.claude/memory/lessons.jsonl` and are shared across every repo,
which is the point: a `set -e` bug learned here is retrievable from anywhere.

## The loop spine (skills + native)

| Need | Reach for |
|---|---|
| A small task | *just ask* — the default delegates + verifies, no command |
| Run a whole task to done, autonomously | `/run-loop "<goal>"` |
| Agree on "done" before code | `/contract` → `.loops/contract.md` |
| Verify a change end-to-end | `/verify` |
| Score subjective quality | `/taste` |
| Parallel builders in isolated checkouts | `/worktree` |
| Measurable loop with a stop | native `/goal` |
| Recurring / scheduled work | native `/loop`, `/schedule` |
| Fan-out + adversarial verify | native `Workflow` |
| Second-agent review | native `/code-review` + `evaluator` |

Domain tracks: `data`, `debug`, `testing`, `llm-agent`.

## State on disk

Every run keeps its state in `.loops/` so it survives crashes and compaction —
recoverable from three files (Karpathy's test):

```bash
loops init "make the ingestion pipeline idempotent"
loops status
```

- `contract.md` — the graded boundary
- `progress.md` — current state, overwritten each iteration
- `log.md` — append-only trace
- `feature_list.json` — the metric and score history, for `/goal` runs
- `verify.sh` — the mechanical checks the contract is graded by

Those five are durable and tracked. Anything else a run leaves behind is debris.

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

## Rules for agents

These are not style preferences. Each one is here because ignoring it has already
cost a run in this repo.

**Verify by running, never by reading.** Four deploy defects shipped past code
review here and were all found in the first minute of actually installing the
thing. If you did not execute it, you do not know it works — say so instead.

**Never grade your own output.** Grading goes to a fresh `evaluator` with its own
context. A builder that scores itself converges on slop.

**A check that has only ever passed is not a check.** Break the thing the check
guards and confirm the check fails. The orchestrator picks the mutations — builder
self-reported mutation tables in this repo have been wrong every time.

**Watch for silent-empty-success.** The recurring defect shape here is *doing
nothing and exiting 0*: a copy that fails unnoticed, a list that finds no files in
a foreign directory, a guard that never fires. If a command can do nothing, prove
it exits non-zero when it should.

**Guard every command substitution whose failure you intend to handle.** Under the
inherited `set -euo pipefail`, a bare `x=$(cmd)` dies before your `$?` check ever
runs. Write it as:

```bash
if x=$(cmd); then status=0; else status=$?; fi
```

**Branch and commit before you experiment.** `git checkout <file>` on uncommitted
work destroys it with no reflog entry.

**Report what you did not do.** Partial coverage stated plainly beats implied
completeness. Name the blocker.

### Environment constraints

- **macOS bash 3.2.57** — no associative arrays, no `mapfile`/`readarray`, no
  `${var^^}`. BSD `readlink` has no `-f`. `timeout` is not installed; bound a
  hanging command with a background process and `kill` instead.
- **Model access is through a gateway** configured entirely in the environment.
  Never write a base URL or token value into a repo file. Roughly 11 s of fixed
  overhead per API round trip, so the only latency lever is fewer round trips.
- `haiku` / `sonnet` / `opus` are Claude Code aliases and do not appear in
  `loops models available`; both are valid values for `loops models set`.
- **`Agent(isolation: "worktree")` branches `origin/main`, not session HEAD.** A
  worktree builder can write against uncommitted work but cannot behaviorally test
  against it. Verification-heavy builders belong in the main checkout.

## Layout

```
.claude/    CLAUDE.md · settings.json · dispatch.md · hooks/ · agents/ · skills/
lib/        models.sh · engine.sh · agent-wait.sh
templates/  contract.md · progress.md · log.md · feature_list.json
run.sh · install.sh · MEMORY.md · README.md
```
