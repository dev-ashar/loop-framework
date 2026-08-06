---
name: worktree
description: Detect hazards in git worktrees, provision safe worktrees, remediate detected issues, and open PRs with fixes. All operations fail closed on dirty trees unless --force is passed.
---

# worktree

Detects and remediates git worktree hazards that block commit operations in fresh linked worktrees. Use for multi-repo health checks and for preparing parallel builder isolation.

## Subcommands

- **check** — read-only scan emitting machine-readable hazard tokens
- **provision** — create a new worktree only if safe (or with --force)
- **fix** — remediate detected hazards in place
- **reap** — report and prune orphaned worktrees

All modify operations (provision, fix) fail closed on a dirty tree unless `--force` is passed.

## Hazard vocabulary

Fixed token set emitted by `check`:

- `HARDCODED_HOOK_PATH` — git hook contains an absolute path, will break in a fresh worktree
- `HOOKS_PATH_ABSOLUTE` — `core.hooksPath` is absolute
- `MISSING_ENV_FILE` — a gitignored `.env*` file referenced by code is present; not auto-fixable
- `MISSING_BOOTSTRAP_ARTIFACT` — gitignored build/dependency dir present (`node_modules/`, `.terraform/`, `env/`, `venv/`, `.venv/`)

## Usage

```bash
# Scan for hazards (read-only)
run.sh worktree check [path]

# Create worktree only if safe
run.sh worktree provision <branch>
run.sh worktree provision <branch> --force  # create despite hazards

# Fix detected hazards in place
run.sh worktree fix
run.sh worktree fix --force  # fix despite dirty tree

# Open a PR with the fix
run.sh worktree provision <branch> --pr

# Report and prune orphaned worktrees
run.sh worktree reap [path]
run.sh worktree reap [path] --prune
```

## Safety gates

- **Secret files are never staged.** `worktree fix` and `provision --pr` will NEVER stage or commit files matching secret patterns (`.env*`, `*.pem`, `*.key`, etc.). `MISSING_ENV_FILE` is reported for human intervention only.
- **No blanket staging.** Every `git add` uses an explicit path, never `git add -A`, `git add .`, `git add -u`, or `git commit -a`.
- **Dirty tree blocks by default.** Provision and fix require a clean tree unless `--force` is passed, preventing accidental staging of unrelated changes.

## Remediation details

### HARDCODED_HOOK_PATH

Rewrites absolute interpreter paths in git hooks to derive from the main worktree:
```bash
MAIN_WT=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")
INSTALL_PYTHON="$MAIN_WT/env/bin/python3.12"
```

Critical: uses `--git-common-dir`, NOT `--show-toplevel`. From inside a linked worktree, `--show-toplevel` resolves to the linked worktree itself where shared resources like `env/` do not exist.

### HOOKS_PATH_ABSOLUTE

Unsets absolute `core.hooksPath`:
```bash
git config --unset core.hooksPath
```

### MISSING_ENV_FILE

Reported only, never auto-fixed. Secrets stay a human step.

### MISSING_BOOTSTRAP_ARTIFACT

Reported only. Provision warns about the bootstrap cost but does not auto-run `npm install` / `terraform init` / `pip install` — that's a per-repo human decision.

## PR workflow

When `provision <branch> --pr` is invoked:

1. Run `worktree check` to enumerate hazards
2. Create the worktree on `<branch>`
3. Apply `worktree fix` remediations
4. Stage ONLY the modified paths via explicit `git add <path>`
5. Commit with a message listing the remediated hazards
6. Invoke `gh pr create --draft --body <summary>` where the body names every detected hazard token
7. Record the returned PR URL to `.loops/log.md` via `run.sh log`

The PR body must name exactly the hazards that `check` emitted for that repo — every triggered token present AND every untriggered token absent. A body that always lists all tokens regardless of what was detected is incorrect.
