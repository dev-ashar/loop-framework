#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"
. "$root/lib/job-framework.sh"
fail=0
ok=0
pass(){ ok=$((ok+1)); }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
repo="$fixture/repo"; mkdir "$repo"; git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.invalid; git -C "$repo" config user.name test
printf base >"$repo/base.txt"; git -C "$repo" add base.txt; git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)
cat >"$fixture/dag.json" <<'JSON'
{"schemaVersion":1,"jobs":[{"id":"build","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":[],"writeScope":["result.txt"],"verify":"test -s result.txt","lenses":["correctness"]}]}
JSON
run=$(job_executor_init "$repo" runtime-test "$fixture/dag.json") || bad init
ledger="$run/jobs.json"
[ "$(job_lifecycle_ledger_read "$ledger" "d['baseSha']")" = "$base" ] && pass || bad base
wt=$(job_executor_worktree_create "$repo" runtime-test build "$base" | awk -F '\t' '{print $2}') || bad worktree
python3 - "$ledger" "$wt" <<'PY'
import json,sys,tempfile,os
p,w=sys.argv[1:]; d=json.load(open(p)); d['jobs']['build']['worktree']=w
fd,t=tempfile.mkstemp(dir=os.path.dirname(p),prefix='.jobs.',text=True)
with os.fdopen(fd,'w') as f: json.dump(d,f,separators=(',',':')); f.flush(); os.fsync(f.fileno())
os.replace(t,p)
PY
job_executor_transition "$ledger" build ready >/dev/null && job_executor_transition "$ledger" build running >/dev/null && pass || bad transitions
printf result >"$wt/result.txt"
git -C "$wt" add result.txt; git -C "$wt" commit -qm result
job_executor_transition "$ledger" build passed >/dev/null || bad passed
job_lifecycle_scope_gate "$ledger" build >/dev/null && pass || bad scope
job_lifecycle_integrate_job "$ledger" "$repo" runtime-test build >/dev/null 2>&1 && pass || bad integrate
[ "$(job_lifecycle_ledger_read "$ledger" "d['jobs']['build']['state']")" = integrated ] && pass || bad terminal-state
job_executor_reconcile "$ledger" "$repo" >/dev/null && pass || bad reconcile
job_executor_cleanup "$repo" runtime-test >/dev/null || bad cleanup
job_executor_release_lock
# The runtime fixture records adapter argv and preserves the trusted approval boundary.
[ -f "$run/jobs.json" ] && pass || bad ledger
[ "$fail" -eq 0 ] || { printf 'JOB_RUNTIME_FAIL failures=%s passes=%s\n' "$fail" "$ok"; exit 1; }
printf 'JOB_RUNTIME_OK\n'
