#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"
source "$root/lib/job-executor.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
repo="$t/repo"; mkdir "$repo"; git -C "$repo" init -q; git -C "$repo" config user.email test@example.com; git -C "$repo" config user.name test
printf 'base\n' >"$repo/base.txt"; git -C "$repo" add base.txt; git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)
cat >"$t/dag.json" <<JSON
{"schemaVersion":2,"jobs":[{"id":"a","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["a.txt"],"verify":"true","lenses":["correctness"]},{"id":"b","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["b.txt"],"verify":"true","lenses":["scope"]}]}
JSON
runid=run-test
run=$(job_executor_init "$repo" "$runid" "$t/dag.json")
ledger="$run/jobs.json"
[ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["baseSha"])' "$ledger")" = "$base" ]
[ -f "$run/jobs.lock" ]
if (job_executor_acquire_lock "$run") 2>/dev/null; then exit 1; fi
for jid in a b; do eval "$(job_executor_worktree_create "$repo" "$runid" "$jid" "$base" | awk -F '\t' '{print "x"NR"=" $2}')"; done
wt_a="$repo/.loops/runs/$runid/worktrees/a"; wt_b="$repo/.loops/runs/$runid/worktrees/b"
[ "$(git -C "$wt_a" rev-parse HEAD)" = "$base" ] && [ "$(git -C "$wt_b" rev-parse HEAD)" = "$base" ]
before=$(mktemp); job_executor_snapshot_main "$repo" "$before" >/dev/null
job_executor_run_batch "$repo" "$ledger" "a:printf 'a-start %s\\n' \"$(date +%s%N)\" > a.txt; sleep 0.3" "b:printf 'b-start %s\\n' \"$(date +%s%N)\" > b.txt; sleep 0.3"
job_executor_main_unchanged "$repo" "$before"
[ "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["jobs"]["a"]["state"]+d["jobs"]["b"]["state"])' "$ledger")" = passedpassed ]
cat >"$t/invalid-ledger.json" <<JSON
{"runId":"x","jobs":{"a":{"state":"passed"}}}
JSON
if job_executor_transition "$t/invalid-ledger.json" a running 2>/dev/null; then exit 1; fi
printf 'x\n' >"$wt_a/new.txt"; git -C "$wt_a" add new.txt
paths=$(job_executor_git_paths "$wt_a" "$base"); printf '%s\n' "$paths" | grep -qx new.txt
job_executor_cleanup "$repo" "$runid"
[ ! -e "$wt_a" ] && [ ! -e "$wt_b" ]
job_executor_release_lock
printf 'JOB_EXECUTOR_OK\n'
