#!/usr/bin/env bash
# Shell primitives for executing validated builder DAG jobs.
# Callers own error policy and provide commands for worker processes.

job_executor_root() {
  if [ -n "${1:-}" ]; then (cd "$1" 2>/dev/null && pwd -P); else git rev-parse --show-toplevel; fi
}

job_executor_atomic_write() {
  local file=$1 data=$2 dir tmp
  dir=$(dirname "$file"); mkdir -p "$dir" || return 1
  tmp=$(mktemp "$dir/.jobs.XXXXXX") || return 1
  printf '%s\n' "$data" >"$tmp" || { rm -f "$tmp"; return 1; }
  python3 - "$tmp" <<'PY'
import os,sys
with open(sys.argv[1],'rb') as f:
 f.flush(); os.fsync(f.fileno())
PY
  mv -f "$tmp" "$file"
}

job_executor_acquire_lock() {
  local run_dir=$1 lock="$run_dir/jobs.lock"
  mkdir -p "$run_dir" || return 1
  ( set -o noclobber; printf '%s\n' "$$" >"$lock" ) 2>/dev/null || { printf 'RUN_LOCK_CONTENTION\n' >&2; return 1; }
  JOB_EXECUTOR_LOCK=$lock
}

job_executor_release_lock() {
  [ -n "${JOB_EXECUTOR_LOCK:-}" ] && rm -f -- "$JOB_EXECUTOR_LOCK"
  JOB_EXECUTOR_LOCK=
}

job_executor_init() {
  local root=${1:-$(git rev-parse --show-toplevel)} runid=$2 run_dir base dag=${3:-}
  run_dir="$root/.loops/runs/$runid"; mkdir -p "$run_dir" || return 1
  job_executor_acquire_lock "$run_dir" || return 1
  base=$(git -C "$root" rev-parse --verify HEAD) || { job_executor_release_lock; return 1; }
  if [ -n "$dag" ]; then
    python3 - "$dag" "$run_dir/jobs.json" "$base" "$runid" "$root" <<'PY'
import json,os,sys,tempfile
src,out,base,runid,root=sys.argv[1:]
with open(src) as f: d=json.load(f)
jobs={}
for j in d['jobs']:
 jobs[j['id']]={'state':'pending','attempt':0,'pid':None,'baseSha':base,'branch':f"loops/{runid}/{j['id']}",'worktree':os.path.join(root,'.loops','runs',runid,'worktrees',j['id']),'scope':j['writeScope'],'verify':j['verify'],'dependsOn':j['dependsOn'],'startedAt':None,'finishedAt':None,'cleanup':None}
state={'runId':runid,'root':root,'baseSha':base,'jobs':jobs}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(out),prefix='.jobs.',text=True)
with os.fdopen(fd,'w') as f: json.dump(state,f,separators=(',',':')); f.flush(); os.fsync(f.fileno())
os.replace(tmp,out)
PY
  else
    job_executor_atomic_write "$run_dir/jobs.json" "{\"runId\":\"$runid\",\"root\":\"$root\",\"baseSha\":\"$base\",\"jobs\":{}}"
  fi
  JOB_EXECUTOR_RUN_DIR=$run_dir; JOB_EXECUTOR_LEDGER=$run_dir/jobs.json; JOB_EXECUTOR_BASE=$base
  printf '%s\n' "$run_dir"
}

job_executor_transition() {
  local ledger=$1 id=$2 to=$3
  python3 - "$ledger" "$id" "$to" <<'PY'
import json,os,sys,tempfile
p,jid,to=sys.argv[1:]
allowed={'pending':{'ready','blocked'},'ready':{'running','blocked'},'running':{'passed','failed','blocked','conflicted'},'passed':{'integrated','integration-conflicted'}}
with open(p) as f: s=json.load(f)
j=s['jobs'].get(jid); old=j and j.get('state')
if not j: print('JOB_UNKNOWN',file=sys.stderr); raise SystemExit(1)
if to not in allowed.get(old,set()):
 print(f'DAG_RETROACTIVE_TRANSITION job={jid} from={old} to={to}',file=sys.stderr); raise SystemExit(1)
j['state']=to
fd,t=tempfile.mkstemp(dir=os.path.dirname(p),prefix='.jobs.',text=True)
with os.fdopen(fd,'w') as f: json.dump(s,f,separators=(',',':')); f.flush(); os.fsync(f.fileno())
os.replace(t,p)
PY
}

job_executor_reconcile() {
  local ledger=$1 root=${2:-$(git rev-parse --show-toplevel)}
  python3 - "$ledger" "$root" <<'PY'
import json,os,subprocess,sys
p,root=sys.argv[1:]
with open(p) as f:s=json.load(f)
for jid,j in s['jobs'].items():
 if j['state']!='running': continue
 pid=j.get('pid'); wt=j.get('worktree'); br=j.get('branch')
 live=bool(pid and subprocess.run(['kill','-0',str(pid)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0)
 branch=subprocess.run(['git','-C',root,'show-ref','--verify','--quiet',f'refs/heads/{br}']).returncode==0
 if not (live and wt and os.path.isdir(wt) and branch):
  print(f'RESTART_EVIDENCE_CONTRADICTORY job={jid}',file=sys.stderr); raise SystemExit(1)
print('RECONCILE_OK')
PY
}

job_executor_ready() {
  local ledger=$1
  python3 - "$ledger" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); jobs=s['jobs']; bad={'failed','blocked','conflicted','integration-conflicted'}
for jid in sorted(jobs):
 j=jobs[jid]
 if j['state']!='pending': continue
 ds=[jobs[d]['state'] for d in j['dependsOn']]
 if any(x in bad for x in ds): print(jid+'\tblocked')
 elif all(x=='passed' or x=='integrated' for x in ds): print(jid+'\tready')
PY
}

job_executor_worktree_create() {
  local root=$1 runid=$2 jid=$3 base=$4 wt br
  br="loops/$runid/$jid"
  wt="$root/.loops/runs/$runid/worktrees/$jid"
  git -C "$root" show-ref --verify --quiet "refs/heads/$br" && return 1
  mkdir -p "$(dirname "$wt")" || return 1
  git -C "$root" worktree add --detach "$wt" "$base" >/dev/null || return 1
  git -C "$wt" switch -c "$br" >/dev/null || { git -C "$root" worktree remove --force "$wt"; return 1; }
  printf '%s\t%s\n' "$br" "$wt"
}

job_executor_git_paths() {
  local wt=$1 base=$2
  { git -C "$wt" diff --name-status -M -C "$base" HEAD; git -C "$wt" diff --name-status -M -C; git -C "$wt" diff --cached --name-status -M -C; git -C "$wt" status --porcelain=v1 -uall; } |
  python3 -c 'import sys
for line in sys.stdin:
 line=line.rstrip("\\n")
 if not line: continue
 if line[:2] in ("??","!!"): print(line[3:])
 else:
  x=line[3:].split(" -> ")
  print(x[-1])
' | sort -u
}

job_executor_snapshot_main() {
  local root=$1 out=$2
  { git -C "$root" rev-parse HEAD; git -C "$root" diff --binary; git -C "$root" diff --cached --binary; git -C "$root" status --porcelain=v1 -uall; git -C "$root" ls-files -s; } >"$out"
  sha256sum "$out" | cut -d' ' -f1
}

job_executor_main_unchanged() {
  local root=$1 before=$2 now
  now=$(mktemp); job_executor_snapshot_main "$root" "$now" >/dev/null
  cmp -s "$before" "$now"; local rc=$?; rm -f "$now"; return $rc
}

job_executor_run_batch() {
  local root=$1 ledger=$2; shift 2
  [ "$#" -le 4 ] || { echo 'JOB_CONCURRENCY_LIMIT' >&2; return 1; }
  local pids=() specs spec jid wt cmd
  for spec in "$@"; do
    jid=${spec%%:*}; cmd=${spec#*:}; wt=$(python3 - "$ledger" "$jid" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['jobs'][sys.argv[2]]['worktree'])
PY
) || return 1
    job_executor_transition "$ledger" "$jid" ready || return 1
    job_executor_transition "$ledger" "$jid" running || return 1
    (cd "$wt" && bash -c "$cmd") & pids+=("$!:$jid")
  done
  local x rc=0
  for x in "${pids[@]}"; do jid=${x#*:}; p=${x%%:*}; if wait "$p"; then job_executor_transition "$ledger" "$jid" passed || rc=1; else job_executor_transition "$ledger" "$jid" failed || rc=1; fi; done
  return "$rc"
}

job_executor_cleanup() {
  local root=$1 runid=$2 ledger wt br jid
  ledger="$root/.loops/runs/$runid/jobs.json"
  [ -f "$ledger" ] || return 0
  while IFS=$'\t' read -r jid wt br; do
    [ -n "$wt" ] && [ -d "$wt" ] && git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || true
    [ -n "$br" ] && git -C "$root" branch -D "$br" >/dev/null 2>&1 || true
  done < <(python3 - "$ledger" <<'PY'
import json,sys
for jid,j in json.load(open(sys.argv[1]))['jobs'].items(): print(jid+'\t'+str(j.get('worktree') or '')+'\t'+str(j.get('branch') or ''))
PY
)
  rm -f "$root/.loops/runs/$runid/jobs.lock" "$root/.loops/runs/$runid"/.jobs.* 2>/dev/null || true
}
