#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
[ "$#" -eq 0 ] || { echo "usage: bash .loops/verify.sh" >&2; exit 2; }
test -f .loops/verify.sh || { echo "verify.sh missing: repository defect" >&2; exit 1; }

# Runtime checks execution boundaries. Review semantics belong to the architect.

# The phase-4 pre-build snapshot guard is gone with the phase-4 run. It only ever
# checksummed its own copies of the files, so it proved the snapshot was intact
# rather than that the originals were unchanged, and the CLAUDE.md diff pinned one
# section verbatim forever. Both are debris, not guards.

# The five durable files are the whole tracked footprint of a run. Anything else
# under .loops/ is per-run scratch and must not reach the index.
tracked=$(git ls-files .loops)
expected='.loops/contract.md
.loops/feature_list.json
.loops/log.md
.loops/progress.md
.loops/verify.sh'
[ "$tracked" = "$expected" ] || { echo "FAIL: .loops/ tracks more than the durable five:"; printf '%s\n' "$tracked"; exit 1; }

bash -n run.sh lib/job-*.sh
bash tests/engine.sh
bash tests/models.sh
bash tests/job-omp.sh
bash tests/bench/validate.sh
bash tests/job-framework.sh
bash tests/job-executor.sh
bash tests/job-dispatch.sh
bash tests/job-integration.sh
bash tests/job-lifecycle.sh
bash tests/job-runtime.sh
git diff --check
printf "%s\n" VERIFY_OK
