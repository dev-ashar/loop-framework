# Progress

## Architecture migration

Status: implementation complete. Verification is in progress.

- Retired the trace CLI surface.
- Removed runtime dependencies on approval, envelope, and report grammar.
- Kept DAG validation, canonical job context, scope checks, and worktree isolation.
- Changed lifecycle readiness to accept completed dependency work.
- Changed restart reconciliation to report neutral evidence outcomes.
- Added per-job review-lens artifacts for parallel review planning.
- Preserved installer behavior and rollback implementation.
