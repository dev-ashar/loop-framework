#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Invariants: profile routing uses concrete argv model; terminal writes reject late results.
# Invariants: output authority accepts once; consumption and final answer record digests.
# Invariants: cancellation permits replacement accounting; reconciliation reports counters.
source "$ROOT/lib/job-dispatch.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
job_dispatch_init dispatch-test "$t"
model=$(job_dispatch_model worker-default operational)
[ "$model" = gpt-5.6-luna-mantle ]
export JOB_DISPATCH_PROFILE=worker-default JOB_DISPATCH_TIER=operational JOB_DISPATCH_MODEL="$model"
token=$(job_dispatch_create d1 agent-1 worker 'write source' input-1 worker-report result-one lib/a.sh '' final 3 stop 1)
job_dispatch_result d1 passed 1 "$token" deadbeef
job_dispatch_accept_output d1 result-one worker-report deadbeef
job_dispatch_consume d1 result-one reviewer
job_dispatch_final_answer final deadbeef
if job_dispatch_result d1 passed 1 "$token" deadbeef 2>/dev/null; then exit 1; fi
job_dispatch_reconcile | grep -q 'DISPATCH_RECONCILED'
job_dispatch_create d2 agent-2 worker 'replace source' input-2 worker-report result-two lib/b.sh '' final 2 stop 1 >/dev/null
job_dispatch_cancel d2
job_dispatch_replace d2 d3 agent-3 | grep -qx '2'
job_dispatch_show | python3 -c 'import json,sys; x=json.load(sys.stdin); assert x["final"]["digests"]==["deadbeef"]; assert x["counters"]["acceptedOutputs"]==1'
printf '%s\n' JOB_DISPATCH_OK
