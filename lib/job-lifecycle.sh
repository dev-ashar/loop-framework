#!/usr/bin/env bash
# DAG job lifecycle glue: integration-gated readiness, transitive blocking
# propagation, the scope/reviewer/integration gate sequence, and restart
# reconciliation. Built on top of lib/job-framework.sh (validation, scope
# grammar), lib/job-executor.sh (ledger transitions, worktrees, snapshots),
# and lib/job-integration.sh (disposable merge, conflict evidence).
#
# Callers retain shell error policy. This file only defines functions.

job_lifecycle_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# shellcheck source=./job-framework.sh
[ -n "${job_framework_root:-}" ] || . "$job_lifecycle_root/lib/job-framework.sh"
# shellcheck source=./job-executor.sh
declare -F job_executor_transition >/dev/null || . "$job_lifecycle_root/lib/job-executor.sh"
# shellcheck source=./job-integration.sh
declare -F job_integration_run >/dev/null || . "$job_lifecycle_root/lib/job-integration.sh"

job_lifecycle_ledger_read() {
  # job_lifecycle_ledger_read <ledger> <python-expr-on-loaded-json-as-d>
  python3 - "$1" "$2" <<'PY'
import json,sys
p,expr=sys.argv[1:]
d=json.load(open(p,encoding='utf8'))
print(eval(expr))
PY
}

# Ready jobs use completed dependency work. Integration is a separate host decision.
# A pending job downstream of a failed dependency is reported as blocked.
job_lifecycle_ready() {
  local ledger=$1
  [ -f "$ledger" ] || { echo 'LEDGER_MISSING' >&2; return 1; }
  python3 - "$ledger" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); jobs=s['jobs']
bad={'failed','blocked','conflicted','integration-conflicted'}
for jid in sorted(jobs):
    j=jobs[jid]
    if j['state']!='pending':
        continue
    ds=[jobs[d]['state'] for d in j['dependsOn']]
    if any(x in bad for x in ds):
        print(jid+'\tblocked')
    elif all(x in {'passed','integrated'} for x in ds):
        print(jid+'\tready')
PY
}

# Propagate 'blocked' to every transitive dependent of origin, without
# touching any resource (no worktree, branch, or process action here — that
# is the caller's job once it observes the propagated state). Only 'pending'
# and 'ready' jobs are moved; a job already running, terminal, or blocked is
# left untouched so this never performs a retroactive transition. Prints
# each newly blocked job ID on its own line.
job_lifecycle_block_dependents() {
  local ledger=$1 origin=$2
  [ -f "$ledger" ] && [ -n "$origin" ] || { echo 'usage: job_lifecycle_block_dependents <ledger> <origin-job-id>' >&2; return 2; }
  python3 - "$ledger" "$origin" <<'PY'
import json,os,sys,tempfile
p,origin=sys.argv[1:]
with open(p,encoding='utf8') as f:
    s=json.load(f)
jobs=s['jobs']
if origin not in jobs:
    print('JOB_UNKNOWN',file=sys.stderr); raise SystemExit(1)
children={jid:[] for jid in jobs}
for jid,j in jobs.items():
    for d in j['dependsOn']:
        children.setdefault(d,[]).append(jid)
movable={'pending','ready'}
seen=set(); stack=list(children.get(origin,[])); changed=[]
while stack:
    n=stack.pop()
    if n in seen:
        continue
    seen.add(n)
    if jobs[n]['state'] in movable:
        jobs[n]['state']='blocked'
        changed.append(n)
    stack.extend(children.get(n,[]))
if changed:
    fd,t=tempfile.mkstemp(dir=os.path.dirname(p) or '.',prefix='.jobs.',text=True)
    with os.fdopen(fd,'w') as f:
        json.dump(s,f,separators=(',',':')); f.flush(); os.fsync(f.fileno())
    os.replace(t,p)
for jid in sorted(changed):
    print(jid)
PY
}

# Scope gate: run the existing scope-check grammar against a job's worktree
# while the job still holds the 'running' state (the verify command has
# exited but the ledger has not yet recorded a terminal outcome). A
# violation transitions the job straight to 'failed' — 'passed' is never
# visited, matching the state machine's running -> {passed,failed,...} edges
# — blocks every dependent, and prints the offending paths so the caller
# never dispatches an reviewer or runs integration on a scope-violating
# job. A clean check performs no mutation; the caller records 'passed'.
job_lifecycle_scope_gate() {
  local ledger=$1 jid=$2
  [ -f "$ledger" ] && [ -n "$jid" ] || { echo 'usage: job_lifecycle_scope_gate <ledger> <job-id>' >&2; return 2; }
  local wt base scope_csv
  wt=$(job_lifecycle_ledger_read "$ledger" "d['jobs']['$jid']['worktree']") || return 1
  base=$(job_lifecycle_ledger_read "$ledger" "d['baseSha']") || return 1
  scope_csv=$(python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))["jobs"][sys.argv[2]]["scope"]))' "$ledger" "$jid") || return 1
  local offenders
  if offenders=$(job_scope_check "$wt" "$base" "$scope_csv" 2>&1); then
    return 0
  fi
  job_executor_transition "$ledger" "$jid" failed
  job_lifecycle_block_dependents "$ledger" "$jid" >/dev/null
  printf 'SCOPE_VIOLATION job=%s\n%s\n' "$jid" "$offenders" >&2
  return 1
}

# Integrate one passed, scope-clean job's branch into main via the
# disposable integration worktree. On success the job moves to
# 'integrated'. On a real conflict it moves to 'integration-conflicted',
# every dependent is blocked, the disposable worktree is removed, source
# branches and evidence are retained, and the main worktree is left clean.
job_lifecycle_integrate_job() {
  local ledger=$1 root=$2 run_id=$3 jid=$4
  [ -f "$ledger" ] && [ -n "$root" ] && [ -n "$run_id" ] && [ -n "$jid" ] || {
    echo 'usage: job_lifecycle_integrate_job <ledger> <root> <run-id> <job-id>' >&2; return 2; }
  local base branch records evidence rc
  base=$(job_lifecycle_ledger_read "$ledger" "d['baseSha']") || return 1
  branch=$(job_lifecycle_ledger_read "$ledger" "d['jobs']['$jid']['branch']") || return 1
  records=$(mktemp)
  printf '%s\t%s\n' "$jid" "$branch" > "$records"
  evidence="$root/.loops/runs/$run_id/integration-$jid.conflict"
  rc=0
  job_integration_run "$root" "$base" "$run_id" "$records" "$evidence" || rc=$?
  rm -f "$records"
  if [ "$rc" -eq 10 ]; then
    job_executor_transition "$ledger" "$jid" integration-conflicted
    job_lifecycle_block_dependents "$ledger" "$jid" >/dev/null
    return 10
  fi
  [ "$rc" -eq 0 ] || return 1
  # job_integration_run only rehearses the merge in a disposable worktree
  # created detached from baseSha, and discards it on success — it never
  # advances any ref in $root, by design: main is never touched until the
  # rehearsal proves the merge is conflict-free against that recorded base.
  # If $root's checked-out branch has since moved past baseSha (e.g. a
  # sibling job integrated first), the rehearsal's base no longer reflects
  # main's real tip, so this real merge can still conflict even though the
  # rehearsal passed. Handle that exactly like job_integration_run's own
  # conflict path: record evidence, abort, leave main clean, block
  # dependents, and report 'integration-conflicted' rather than a bare
  # failure.
  local main_branch
  main_branch=$(git -C "$root" symbolic-ref --quiet --short HEAD || echo HEAD)
  if git -C "$root" merge --no-ff --no-edit "$branch" >/dev/null 2>&1 \
     && job_integration_main_clean "$root"; then
    job_executor_transition "$ledger" "$jid" integrated
    return 0
  fi
  local paths path
  paths=$(git -C "$root" diff --name-only --diff-filter=U | LC_ALL=C sort)
  : > "$evidence"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    job_integration_conflict_record "$evidence" "$base" "$main_branch" "$main_branch" "$jid" "$branch" "$path"
  done <<< "$paths"
  [ -s "$evidence" ] || job_integration_conflict_record "$evidence" "$base" "$main_branch" "$main_branch" "$jid" "$branch" unknown
  git -C "$root" merge --abort >/dev/null 2>&1 || true
  job_executor_transition "$ledger" "$jid" integration-conflicted
  job_lifecycle_block_dependents "$ledger" "$jid" >/dev/null
  return 10
}

# Advances a running job through scope validation and integration.
# A scope violation stops before the passed state and before integration.
job_lifecycle_advance_running_job() {
  local ledger=$1 root=$2 run_id=$3 jid=$4
  job_lifecycle_scope_gate "$ledger" "$jid" || return 1
  job_executor_transition "$ledger" "$jid" passed || return 1
  job_lifecycle_integrate_job "$ledger" "$root" "$run_id" "$jid"
}

# Reconciliation reports observed state only. It never converts uncertainty into a gate.
job_lifecycle_restart_reconcile() {
  local ledger=$1 root=$2
  [ -f "$ledger" ] || { echo 'RECONCILIATION_UNKNOWN reason=LEDGER_MISSING'; return 1; }
  local out
  if out=$(job_executor_reconcile "$ledger" "${root:-$(git -C "$(dirname "$ledger")" rev-parse --show-toplevel 2>/dev/null || pwd)}" 2>&1); then
    printf 'RECONCILIATION_CONFIRMED %s\n' "$out"
    return 0
  fi
  printf 'RECONCILIATION_UNKNOWN %s\n' "$out"
  return 1
}

# Terminal-completion cleanup policy: a run in a durable terminal state
# (every job integrated, or the run's only unresolved states are blocked
# with their terminal report already recorded) removes owned locks,
# temporary files, and worktrees. Conflicted jobs and their evidence are
# retained until explicit host-authorized cleanup, so this refuses to run
# while any job is 'conflicted' or 'integration-conflicted'.
# Structured report envelopes are retired. Reports are optional evidence.
job_lifecycle_validate_report() {
  return 0
}
job_lifecycle_compose_lenses() {
  local profile=$1; shift
  python3 - "$job_lifecycle_root/templates/job-profiles.json" "$profile" "$@" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); profile=sys.argv[2]; names=sys.argv[3:]
if profile not in p.get('profiles',{}): profile='worker-default'
if not names or len(names)!=len(set(names)) or any(x not in p.get('lenses',{}) for x in names): raise SystemExit('LENS_INVALID')
for x in names: print(json.dumps(p['lenses'][x],sort_keys=True,separators=(',',':')))
PY
}
job_lifecycle_validate_output_schema() {
  local id=$1; python3 - "$job_lifecycle_root/templates/job-profiles.json" "$id" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); i=sys.argv[2]
if i not in p.get('outputSchemas',{}): print('DISPATCH_OUTPUT_SCHEMA_UNKNOWN id='+i); raise SystemExit(1)
print('OUTPUT_SCHEMA_OK')
PY
}
job_lifecycle_lesson_record() {
  local category=$1 mistake=$2 correction=$3 source_hash=$4 job=${5:-} role=${6:-reviewer} lens=${7:-} status=${8:-active} supersedes=${9:-}
  python3 - "$category" "$mistake" "$correction" "$source_hash" "$job" "$role" "$lens" "$status" "$supersedes" <<'PY'
import hashlib,json,os,re,sys
cat,mis,cor,src,job,role,lens,status,sup=sys.argv[1:]
terms=sorted(set(x for x in re.split(r'[^a-z0-9]+',(cat+' '+mis+' '+cor+' '+job+' '+role).lower()) if x))[:16]
# Canonical event ID is content-only (category/mistake/correction/role) and
# excludes provenance (jobId, sourceEnvelopeHash), so the same lesson learned
# from two different jobs converges on one ID instead of forking duplicates.
canon=(json.dumps({'category':cat,'correction':cor,'mistake':mis,'role':role},ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n').encode()
eid=hashlib.sha256(canon).hexdigest()
p=os.path.join(os.environ.get('HOME',''),'.claude/memory/lessons.jsonl')
os.makedirs(os.path.dirname(p),exist_ok=True)
def already_active():
    if not os.path.exists(p): return False
    for line in open(p,encoding='utf8'):
        line=line.strip()
        if not line: continue
        try: rec=json.loads(line)
        except Exception: continue
        if rec.get('eventId')==eid and rec.get('status')=='active': return True
    return False
# Duplicate suppression: an identical active lesson is never re-appended.
if status=='active' and already_active():
    print(eid); raise SystemExit(0)
e={'category':cat,'correction':cor,'eventId':eid,'jobId':job,'mistake':mis,'relevanceTerms':terms,'role':role,'sourceEnvelopeHash':src,'status':status,'supersedes':sup}
with open(p,'ab') as f: f.write((json.dumps(e,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n').encode())
# Supersession is atomic from the caller's side: recording a new active
# lesson that supersedes an old one also appends the old one's invalidation,
# in the same append-only, immutable log (no record is ever rewritten).
if status=='active' and sup:
    inv={'eventId':hashlib.sha256((eid+'#invalidates#'+sup).encode()).hexdigest(),'status':'invalidated','supersedes':sup}
    with open(p,'ab') as f: f.write((json.dumps(inv,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n').encode())
print(eid)
PY
}
job_lifecycle_lesson_query() {
  local query=$1 category=${2:-} job=${3:-} lenses=${4:-}
  python3 - "$query" "$category" "$job" "$lenses" <<'PY'
import hashlib,json,os,re,sys
q,cat,job,lens=sys.argv[1:]
qt=set(x for x in re.split(r'[^a-z0-9]+',q.lower()) if x)
ls=set(filter(None,lens.split(',')))
p=os.path.join(os.environ.get('HOME',''),'.claude/memory/lessons.jsonl')
if not os.path.exists(p): raise SystemExit('LESSON_IRRELEVANT')
records=[]
for line in open(p,encoding='utf8'):
    line=line.strip()
    if not line: continue
    try: e=json.loads(line)
    except Exception: continue
    digest=hashlib.sha256(line.encode()).hexdigest()
    e.setdefault('eventId',digest)
    records.append(e)
# Two passes: invalidation is append-only and can land anywhere after the
# record it supersedes, so every invalidated id must be known before any
# record is admitted or rejected.
invalid=set(e.get('supersedes') for e in records if e.get('status')=='invalidated' and e.get('supersedes'))
rows=[]; seen_content=set()
for e in records:
    if e.get('status')!='active' or e.get('eventId') in invalid: continue
    if cat and e.get('category')!=cat: continue
    if job and e.get('jobId')!=job: continue
    if ls and not ls.intersection(set(e.get('lenses',[]))): continue
    terms=set(e.get('relevanceTerms',[])); overlap=len(qt&terms)
    if overlap<2: continue
    sig=hashlib.sha256((str(e.get('category'))+'|'+str(e.get('mistake'))+'|'+str(e.get('correction'))).encode()).hexdigest()
    if sig in seen_content: continue
    seen_content.add(sig)
    rows.append((overlap,e.get('eventId',''),e.get('correction','')))
if not rows: raise SystemExit('LESSON_IRRELEVANT')
for _,_,x in sorted(rows,key=lambda z:(-z[0],z[1]))[:20]: print(x)
PY
}

job_lifecycle_terminal_cleanup() {
  local ledger=$1 root=$2 run_id=$3
  [ -f "$ledger" ] && [ -n "$root" ] && [ -n "$run_id" ] || {
    echo 'usage: job_lifecycle_terminal_cleanup <ledger> <root> <run-id>' >&2; return 2; }
  local blockers
  blockers=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
held={"conflicted","integration-conflicted"}
print("\n".join(j for j,v in d["jobs"].items() if v["state"] in held))' "$ledger")
  if [ -n "$blockers" ]; then
    printf 'CLEANUP_HELD jobs=%s\n' "$(printf '%s' "$blockers" | paste -sd, -)"
    return 1
  fi
  job_executor_cleanup "$root" "$run_id"
  printf 'CLEANUP_OK\n'
}
