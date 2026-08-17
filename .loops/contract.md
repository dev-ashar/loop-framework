# Contract — Phase 5: engine + model configuration CLI

Locked 2026-08-05. Graded by `evaluator` (terra) against this file only.

## Goal

Two new `run.sh` capability groups, built by two builders **running at the same
time in separate worktrees**:

- `run.sh models` — inspect and change which model each role runs on.
- `run.sh engine` — choose between Claude Code and OpenCode as the agent engine,
  and dispatch a role through the chosen one.

Phase 5 is also the first real exercise of the parallel-builder gates built in
Phase 4. The gates must *fire*, not merely exist.

## File allowlist (scope-check enforced)

- Builder A may create/modify **`lib/models.sh`** and nothing else.
- Builder B may create/modify **`lib/engine.sh`** and nothing else.
- The orchestrator, after both merge, wires two `case` arms into `run.sh`.

Any path outside a builder's single allowed file is a scope violation and fails
that builder outright, regardless of code quality.

## Acceptance criteria

### Shared interface contract (both builders)

1. Each file is a POSIX-`bash` library, **sourced**, not executed. It defines
   exactly one entrypoint function — `cmd_models` / `cmd_engine` — taking the
   post-subcommand argv. No top-level side effects at source time: sourcing the
   file must not read a network, write a file, or print anything.
2. The file must not contain `set -euo pipefail` (run.sh already sets it) and
   must not call `exit` from library code paths that a caller may want to
   recover from — return non-zero instead. Usage errors return 1 or 2.
3. Secrets never appear in output. `$ANTHROPIC_AUTH_TOKEN` must not be echoed,
   logged, or written to any file. `grep -c ANTHROPIC_AUTH_TOKEN` on the file may
   match only in a context that passes the value to `curl -H` — never a `printf`,
   `echo`, `>>`, or `tee`.
4. Every subcommand prints a one-line usage string and returns non-zero when
   called with no args or an unknown subcommand.

### D1 — `lib/models.sh` (Builder A)

5. `cmd_models list` — for each `.claude/agents/*.md`, print `role<TAB>model`,
   reading the `model:` key from the YAML frontmatter (the block between the
   first two `---` lines only — a `model:` mention in the prose body must not be
   picked up). Roles with no `model:` key print `(default)`.
6. `cmd_models available` — `GET $ANTHROPIC_BASE_URL/v1/models` with header
   `x-api-key: $ANTHROPIC_AUTH_TOKEN`, print `.data[].id` sorted, one per line.
   On non-zero curl exit or unparseable body, print a diagnostic to stderr and
   return non-zero. Must not print the token in the diagnostic.
7. `cmd_models set <role> <model-id>` — rewrite that role's frontmatter `model:`
   line in place, preserving every other byte of the file. If the role file has
   no `model:` key, insert one as the last line of the frontmatter block.
8. `set` validates: unknown role → non-zero, no write. Model id absent from the
   live HAIP list → non-zero, no write, **unless** `--force` is passed. Prove the
   no-write property: the file's sha256 is unchanged after a rejected `set`.
9. `set` is idempotent — running the same `set` twice leaves the file
   byte-identical to after the first run.

### D2 — `lib/engine.sh` (Builder B)

10. Engine state persists in **`.loops/engine`**, a single line, `claude` or
    `opencode`. Absent file means `claude`. `cmd_engine` creates it only on `set`.
11. `cmd_engine show` — print the active engine and the resolved binary path.
12. `cmd_engine set <claude|opencode>` — reject any other value non-zero. Reject
    with non-zero if the corresponding binary is not on `PATH` (`command -v
    claude` / `command -v opencode`), and do not write the state file in that
    case.
13. `cmd_engine run <role> "<prompt>"` — resolve the role's model from
    `.claude/agents/<role>.md` frontmatter, then exec the active engine headless:
    - claude → `claude --model <model> -p "<prompt>"`
    - opencode → `opencode run -m <model> "<prompt>"`
    Unknown role → non-zero before spawning anything.
14. `cmd_engine run --dry-run <role> "<prompt>"` prints the exact argv it would
    execute, one token per line, and spawns nothing. This is the graded path —
    the evaluator must be able to verify command construction without burning
    tokens or requiring network.

### D3 — parallel-run evidence (orchestrator)

15. `.loops/phase5-parallel.md` records, from the actual run: the two worktree
    paths, both builders' start order in a single dispatch, the `scope-check`
    invocation and exit code for each worktree, and **the integration mechanism
    actually used**, named positively and backed by pasted output.

    *Amended, iteration 1.* This criterion originally said "the merge commands
    used." It presumed a merge. No merge happened or could have: the builders
    were instructed not to commit, so both worktree branches sat at zero commits
    ahead of `origin/main` and the two files were untracked in their worktrees.
    They were integrated with `cp`. The evaluator read the original wording
    literally and failed the criterion for recording a copy instead of a merge —
    which would have required either fabricating a merge record or performing a
    merge purely to satisfy the sentence. Recording the mechanism that actually
    ran is the point; the specific verb was an assumption baked into the
    criterion, so the criterion is what changes. The amendment is disclosed here
    rather than applied silently.
16. `run.sh scope-check` was actually executed against both worktrees and its
    output is pasted verbatim. A transcribed or reconstructed result fails this
    criterion.
17. At least one **negative** scope-check is demonstrated in the same file: an
    intentionally out-of-allowlist path is shown being rejected with a non-zero
    exit. A guard that has only ever returned 0 is not a tested guard.

### D4 — integration (orchestrator, after merge)

18. `run.sh models` and `run.sh engine` are reachable from the top-level `case`
    in `run.sh`, and both appear in the bottom `usage:` string.
19. `bash -n run.sh`, `bash -n lib/models.sh`, `bash -n lib/engine.sh` all pass.
20. `.loops/verify.sh` is extended to cover criteria 5–14 and 18–19
    mechanically, and exits non-zero if any fails.

## Verify

```
bash .loops/verify.sh
```

Mechanical criteria are graded by running that script, not by reading the code.
Criteria 3, 9, and 12 additionally require evaluator judgement.

## Constraints

- No secret values in any repo file. `git grep` for the token value must return
  zero hits before commit.
- `.claude/CLAUDE.md` stays ≤131 lines and its `## Output style` block stays
  byte-identical (anchor by heading-to-next-heading extraction, never by line
  number or fixed count).
- No backward-compatibility shims. This is new surface; build it once, correctly.
- Nothing is pushed, deployed, or published.

## Stop condition

Evaluator returns PASS at ≥0.95 with every mechanical criterion verified by
running the command, not by reading the code.
