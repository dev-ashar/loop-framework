#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../lib/job-lifecycle.sh
. "$root/lib/job-lifecycle.sh"

fail=0
ok=0
pass(){ ok=$((ok+1)); }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
expect_token(){ local name=$1 token=$2; shift 2; local out rc; set +e; out=$("$@" 2>&1); rc=$?; set -e
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -Fq "$token"; then pass; else bad "$name token=$token output=$out rc=$rc"; fi; }

t=$(mktemp -d)
cleanup(){ rm -rf "$t"; }
trap cleanup EXIT

# --- fixture repo and a 3-job chain a -> b -> c, plus an unrelated job d ---
repo="$t/repo"; mkdir "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name test
printf '.loops/\n' > "$repo/.gitignore"
printf 'base\n' > "$repo/base.txt"
git -C "$repo" add .gitignore base.txt
git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)
runid=lifecycle-test
run_dir="$repo/.loops/runs/$runid"
mkdir -p "$run_dir"
ledger="$run_dir/jobs.json"

write_ledger() {
  python3 - "$ledger" "$base" "$runid" <<'PY'
import json,sys
ledger,base,runid=sys.argv[1:]
jobs={
 'a': {'state':'pending','attempt':0,'pid':None,'baseSha':base,'branch':f'loops/{runid}/a','worktree':None,'scope':['a.txt'],'verify':'true','dependsOn':[],'startedAt':None,'finishedAt':None,'cleanup':None},
 'b': {'state':'pending','attempt':0,'pid':None,'baseSha':base,'branch':f'loops/{runid}/b','worktree':None,'scope':['b.txt'],'verify':'true','dependsOn':['a'],'startedAt':None,'finishedAt':None,'cleanup':None},
 'c': {'state':'pending','attempt':0,'pid':None,'baseSha':base,'branch':f'loops/{runid}/c','worktree':None,'scope':['c.txt'],'verify':'true','dependsOn':['b'],'startedAt':None,'finishedAt':None,'cleanup':None},
 'd': {'state':'pending','attempt':0,'pid':None,'baseSha':base,'branch':f'loops/{runid}/d','worktree':None,'scope':['d.txt'],'verify':'true','dependsOn':[],'startedAt':None,'finishedAt':None,'cleanup':None},
}
json.dump({'runId':runid,'root':None,'baseSha':base,'jobs':jobs}, open(ledger,'w'), separators=(',',':'))
PY
}
write_ledger

# Criterion: only roots with no deps are ready; downstream jobs are neither
# ready nor blocked while their ancestor is merely pending.
ready_out=$(job_lifecycle_ready "$ledger")
[ "$(printf '%s\n' "$ready_out" | grep -c $'\tready$')" = 2 ] \
  && printf '%s\n' "$ready_out" | grep -qx $'a\tready' \
  && printf '%s\n' "$ready_out" | grep -qx $'d\tready' \
  && ! printf '%s\n' "$ready_out" | grep -q '^b' \
  && ! printf '%s\n' "$ready_out" | grep -q '^c' \
  && pass || bad 'initial readiness is deps-only, integration-gated'

# Readiness requires 'integrated', not merely 'passed' — a dependency stuck
# at 'passed' must not unblock its dependent.
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["a"]["state"]="passed"; json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
ready_out=$(job_lifecycle_ready "$ledger")
! printf '%s\n' "$ready_out" | grep -q '^b' && pass || bad 'passed-but-not-integrated dependency incorrectly unblocked dependent'

python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["a"]["state"]="integrated"; json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
ready_out=$(job_lifecycle_ready "$ledger")
printf '%s\n' "$ready_out" | grep -qx $'b\tready' && pass || bad 'integrated dependency did not unblock dependent'

# --- block-dependents propagation: failing 'b' must transitively block 'c' ---
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["b"]["state"]="failed"; json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
changed=$(job_lifecycle_block_dependents "$ledger" b)
[ "$changed" = c ] && pass || bad "block-dependents propagation changed=[$changed]"
state_c=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["c"]["state"])' "$ledger")
[ "$state_c" = blocked ] && pass || bad 'dependent state was not written as blocked'
state_d=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["d"]["state"])' "$ledger")
[ "$state_d" = pending ] && pass || bad 'unrelated job was incorrectly blocked'

# A second call is idempotent: nothing left to move, so nothing is reprinted.
changed2=$(job_lifecycle_block_dependents "$ledger" b)
[ -z "$changed2" ] && pass || bad "block-dependents was not idempotent: [$changed2]"

# Unknown origin job fails loudly rather than silently doing nothing.
expect_token 'unknown-origin' JOB_UNKNOWN job_lifecycle_block_dependents "$ledger" no-such-job

write_ledger

# --- scope gate: build real worktrees for a scope-clean and a violating job ---
git -C "$repo" worktree add -q "$run_dir/worktrees/a" -b "loops/$runid/a" "$base"
printf 'a-content\n' > "$run_dir/worktrees/a/a.txt"
git -C "$run_dir/worktrees/a" add a.txt
git -C "$run_dir/worktrees/a" -c user.name=test -c user.email=test@example.invalid commit -qm a
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["a"]["worktree"]=sys.argv[2]; d["jobs"]["a"]["state"]="running"; json.dump(d,open(p,"w"),separators=(",",":"))' \
  "$ledger" "$run_dir/worktrees/a"
job_lifecycle_scope_gate "$ledger" a
[ "$?" -eq 0 ] && pass || bad 'clean scope gate rejected an in-scope job'
state_a=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["a"]["state"])' "$ledger")
[ "$state_a" = running ] && pass || bad 'scope gate mutated state on a clean pass'

git -C "$repo" worktree add -q "$run_dir/worktrees/d" -b "loops/$runid/d" "$base"
printf 'out-of-scope\n' > "$run_dir/worktrees/d/rogue.txt"
git -C "$run_dir/worktrees/d" add rogue.txt
git -C "$run_dir/worktrees/d" -c user.name=test -c user.email=test@example.invalid commit -qm rogue
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["d"]["worktree"]=sys.argv[2]; d["jobs"]["d"]["dependsOn"]=[]; d["jobs"]["d"]["state"]="running"; json.dump(d,open(p,"w"),separators=(",",":"))' \
  "$ledger" "$run_dir/worktrees/d"
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["c"]["dependsOn"]=["d"]; d["jobs"]["c"]["state"]="pending"; d["jobs"]["b"]["state"]="pending"; json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
set +e
scope_err=$(job_lifecycle_scope_gate "$ledger" d 2>&1); scope_rc=$?
set -e
[ "$scope_rc" -ne 0 ] && printf '%s\n' "$scope_err" | grep -qx rogue.txt && pass || bad 'violating scope gate did not report the offending path'
state_d=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["d"]["state"])' "$ledger")
[ "$state_d" = failed ] && pass || bad 'scope violation did not fail the job'
state_c=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["c"]["state"])' "$ledger")
[ "$state_c" = blocked ] && pass || bad 'scope violation did not block its dependent'

# --- integrate_job: a clean single-job integration reaches 'integrated' ---
write_ledger
git -C "$repo" worktree remove --force "$run_dir/worktrees/a" >/dev/null 2>&1 || true
git -C "$repo" worktree remove --force "$run_dir/worktrees/d" >/dev/null 2>&1 || true
git -C "$repo" branch -D "loops/$runid/a" "loops/$runid/d" >/dev/null 2>&1 || true
git -C "$repo" worktree add -q "$run_dir/worktrees/a" -b "loops/$runid/a" "$base"
printf 'a-content\n' > "$run_dir/worktrees/a/a.txt"
git -C "$run_dir/worktrees/a" add a.txt
git -C "$run_dir/worktrees/a" -c user.name=test -c user.email=test@example.invalid commit -qm a
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["a"]["state"]="running"; d["jobs"]["a"]["worktree"]=sys.argv[2]; json.dump(d,open(p,"w"),separators=(",",":"))' \
  "$ledger" "$run_dir/worktrees/a"
job_lifecycle_advance_running_job "$ledger" "$repo" "$runid" a
[ "$?" -eq 0 ] && pass || bad 'clean advance-running-job did not succeed'
state_a=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["a"]["state"])' "$ledger")
[ "$state_a" = integrated ] && pass || bad "advance-running-job left state=$state_a instead of integrated"
[ "$(git -C "$repo" cat-file -p HEAD:a.txt 2>/dev/null)" = a-content ] && pass || bad 'integrated content did not reach main'
git -C "$repo" show-ref --verify --quiet "refs/heads/loops/$runid/a" && pass || bad 'integration deleted the source branch'
[ "$(git -C "$repo" status --porcelain)" = '' ] && pass || bad 'main worktree dirty after integration'
[ ! -d "$run_dir/integration-worktree" ] && pass || bad 'disposable integration worktree not cleaned up'

# reset main to base for the conflict scenario
git -C "$repo" reset -q --hard "$base"
git -C "$repo" clean -qfd -e .loops -e "loops" >/dev/null 2>&1 || true

# --- integrate_job: a real same-line conflict yields integration-conflicted
# and blocks the dependent, retaining source evidence and a clean main ---
write_ledger
git -C "$repo" worktree remove --force "$run_dir/worktrees/a" >/dev/null 2>&1 || true
git -C "$repo" branch -D "loops/$runid/a" >/dev/null 2>&1 || true
printf 'shared\n' > "$repo/shared.txt"
git -C "$repo" add shared.txt
git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -qm shared
base2=$(git -C "$repo" rev-parse HEAD)
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["baseSha"]=sys.argv[2]
for j in d["jobs"].values(): j["baseSha"]=sys.argv[2]
json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger" "$base2"
git -C "$repo" checkout -qb "loops/$runid/a" "$base2"
printf 'left\n' >> "$repo/shared.txt"
git -C "$repo" commit -qam left
git -C "$repo" checkout -qb "loops/$runid/prior" "$base2"
printf 'right\n' >> "$repo/shared.txt"
git -C "$repo" commit -qam right
git -C "$repo" checkout -q main
git -C "$repo" merge --no-ff --no-edit "loops/$runid/prior" -q
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["a"]["state"]="passed"; d["jobs"]["a"]["worktree"]=None
d["jobs"]["c"]["dependsOn"]=["a"]; json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
main_before=$(git -C "$repo" rev-parse HEAD)
set +e
job_lifecycle_integrate_job "$ledger" "$repo" "$runid" a
conflict_rc=$?
set -e
[ "$conflict_rc" -eq 10 ] && pass || bad "conflicting integration returned rc=$conflict_rc, want 10"
state_a=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["a"]["state"])' "$ledger")
[ "$state_a" = integration-conflicted ] && pass || bad "conflicted job state=$state_a"
state_c=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobs"]["c"]["state"])' "$ledger")
[ "$state_c" = blocked ] && pass || bad 'conflict did not block its dependent'
git -C "$repo" show-ref --verify --quiet "refs/heads/loops/$runid/a" && pass || bad 'conflict removed the source branch'
[ "$(git -C "$repo" status --porcelain)" = '' ] && [ "$(git -C "$repo" rev-parse HEAD)" = "$main_before" ] && pass || bad 'main worktree changed after conflict'
[ ! -d "$run_dir/integration-worktree" ] && pass || bad 'conflict left the disposable integration worktree behind'
[ -f "$run_dir/integration-a.conflict" ] && grep -q 'conflicted_path=shared.txt' "$run_dir/integration-a.conflict" && pass || bad 'conflict evidence file missing or incomplete'

# --- retroactive transition guard is inherited, not bypassed ---
expect_token 'retroactive-guard' DAG_RETROACTIVE_TRANSITION job_executor_transition "$ledger" a running

# --- restart reconciliation: contradictory evidence blocks without mutation ---
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["jobs"]["d"]["state"]="running"; d["jobs"]["d"]["pid"]=999999999; d["jobs"]["d"]["worktree"]="/no/such/path"; d["jobs"]["d"]["branch"]="loops/no-such/branch"
json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
sha_before=$(shasum -a 256 "$ledger" | awk '{print $1}')
set +e
reconcile_out=$(job_lifecycle_restart_reconcile "$ledger" "$repo" 2>&1); reconcile_rc=$?
set -e
[ "$reconcile_rc" -ne 0 ] && printf '%s\n' "$reconcile_out" | grep -q BLOCKED && pass || bad "restart reconciliation did not block on contradictory evidence: $reconcile_out"
sha_after=$(shasum -a 256 "$ledger" | awk '{print $1}')
[ "$sha_before" = "$sha_after" ] && pass || bad 'blocked reconciliation mutated the ledger'

# --- terminal cleanup: held while a job is integration-conflicted or conflicted ---
set +e
cleanup_out=$(job_lifecycle_terminal_cleanup "$ledger" "$repo" "$runid" 2>&1); cleanup_rc=$?
set -e
[ "$cleanup_rc" -ne 0 ] && printf '%s\n' "$cleanup_out" | grep -q CLEANUP_HELD && pass || bad 'terminal cleanup ran while a job was integration-conflicted'
[ -f "$run_dir/integration-a.conflict" ] && pass || bad 'held cleanup deleted retained conflict evidence'

# Clear the held state and confirm cleanup then proceeds.
python3 -c 'import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["jobs"]["a"]["state"]="integrated"; d["jobs"]["d"]["state"]="failed"
json.dump(d,open(p,"w"),separators=(",",":"))' "$ledger"
cleanup_out2=$(job_lifecycle_terminal_cleanup "$ledger" "$repo" "$runid")
printf '%s\n' "$cleanup_out2" | grep -q CLEANUP_OK && pass || bad 'terminal cleanup did not proceed once unblocked'
[ ! -d "$run_dir/worktrees" ] || [ -z "$(find "$run_dir/worktrees" -mindepth 1 -maxdepth 1 2>/dev/null)" ] && pass || bad 'terminal cleanup left worktrees behind'

# --- envelope-before-grammar hook: reject before checking role grammar ---
export HOME="$t/home"; mkdir -p "$HOME"
set +e
job_lifecycle_validate_report "$t/no-such-report" corr1 "$runid" builder task1 contracthash builder-report >/dev/null 2>&1
report_rc=$?
set -e
[ "$report_rc" -ne 0 ] && pass || bad 'validate_report accepted a missing envelope'

# --- evaluator lens/schema validation ---
lens_out=$(job_lifecycle_compose_lenses builder correctness scope)
printf '%s\n' "$lens_out" | grep -q 'Correctness' && printf '%s\n' "$lens_out" | grep -q 'scope' \
  && pass || bad 'compose_lenses did not resolve known lens names'
expect_token 'lens-unknown' LENS_INVALID job_lifecycle_compose_lenses builder no-such-lens
expect_token 'lens-duplicate' LENS_INVALID job_lifecycle_compose_lenses builder correctness correctness

schema_id=$(python3 -c "import json;print(list(json.load(open('$root/templates/job-profiles.json'))['outputSchemas'].keys())[0])")
job_lifecycle_validate_output_schema "$schema_id" | grep -q OUTPUT_SCHEMA_OK && pass || bad 'validate_output_schema rejected a known schema id'
expect_token 'schema-unknown' DISPATCH_OUTPUT_SCHEMA_UNKNOWN job_lifecycle_validate_output_schema no-such-schema

# --- canonical lesson events/IDs, bounded retrieval, generic/irrelevant
# rejection, duplicate suppression, immutable supersession/invalidation,
# deterministic query ordering ---
eid1=$(job_lifecycle_lesson_record scope 'used wrong worktree' 'always resolve worktree from ledger' hash1 jobA builder)
eid_dup=$(job_lifecycle_lesson_record scope 'used wrong worktree' 'always resolve worktree from ledger' hash2 jobB builder)
[ "$eid1" = "$eid_dup" ] && pass || bad 'canonical event id was not stable across provenance-only differences'
lesson_file="$HOME/.claude/memory/lessons.jsonl"
[ "$(grep -c "\"eventId\":\"$eid1\"" "$lesson_file")" = 1 ] && pass || bad 'duplicate lesson content was appended again instead of suppressed'

query_out=$(job_lifecycle_lesson_query 'wrong worktree scope resolve')
[ "$(printf '%s\n' "$query_out" | wc -l | tr -d ' ')" = 1 ] \
  && printf '%s\n' "$query_out" | grep -qx 'always resolve worktree from ledger' \
  && pass || bad 'lesson query did not return exactly one deduped, relevant result'

expect_token 'lesson-irrelevant' LESSON_IRRELEVANT job_lifecycle_lesson_query 'totally unrelated banana zephyr'

eid2=$(job_lifecycle_lesson_record scope 'used wrong worktree' 'resolve worktree strictly from ledger.worktree field' hash3 jobA builder '' active "$eid1")
[ -n "$eid2" ] && [ "$eid2" != "$eid1" ] && pass || bad 'superseding lesson record did not mint a new canonical id'
query_out2=$(job_lifecycle_lesson_query 'wrong worktree scope resolve')
printf '%s\n' "$query_out2" | grep -qx 'resolve worktree strictly from ledger.worktree field' \
  && ! printf '%s\n' "$query_out2" | grep -qx 'always resolve worktree from ledger' \
  && pass || bad 'supersession did not immutably invalidate the superseded lesson at query time'

# Deterministic ordering: repeated identical queries return the same order.
run1=$(job_lifecycle_lesson_query 'wrong worktree scope resolve')
run2=$(job_lifecycle_lesson_query 'wrong worktree scope resolve')
[ "$run1" = "$run2" ] && pass || bad 'lesson query ordering was not deterministic across repeated calls'

# Bounded retrieval: never return more than 20 rows even with many matches.
for i in $(seq 1 25); do
  job_lifecycle_lesson_record scope "mistake $i worktree scope" "correction $i worktree scope resolve" "hash$i" "job$i" builder >/dev/null
done
bounded_out=$(job_lifecycle_lesson_query 'worktree scope resolve mistake correction')
[ "$(printf '%s\n' "$bounded_out" | wc -l | tr -d ' ')" -le 20 ] && pass || bad 'lesson query was not bounded to at most 20 results'

if [ "$fail" -ne 0 ]; then
  printf 'JOB_LIFECYCLE_FAIL failures=%s passes=%s\n' "$fail" "$ok"
  exit 1
fi
printf 'JOB_LIFECYCLE_OK\n'
