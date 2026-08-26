#!/usr/bin/env bash
# Validated DAG runtime. Callers retain shell error policy.
job_framework_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
job_dag_schema="$job_framework_root/templates/job-dag.schema.json"
job_profiles_file="$job_framework_root/templates/job-profiles.json"
. "$job_framework_root/lib/job-executor.sh"
. "$job_framework_root/lib/job-dispatch.sh"
. "$job_framework_root/lib/job-lifecycle.sh"
. "$job_framework_root/lib/job-integration.sh"

job_json_unique_keys() {
 python3 - "$1" <<'PY'
import json,sys
class D(dict):
 def __init__(self,pairs=()):
  if len([x[0] for x in pairs])!=len(set(x[0] for x in pairs)): raise ValueError('DUPLICATE_JSON_KEY')
  super().__init__(pairs)
try:
 with open(sys.argv[1],encoding='utf-8') as f: json.load(f,object_pairs_hook=D)
except Exception as e: print(str(e),file=sys.stderr); raise SystemExit(1)
PY
}
job_validate_profiles() {
 local file="${1:-$job_profiles_file}"; job_json_unique_keys "$file" || { echo PROFILE_DUPLICATE_KEY; return 1; }
 python3 - "$file" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf8')); allowed={'read-source','write-source','run-tests','git-read','git-worktree','memory-read','memory-write'}
if set(p)!= {'schemaVersion','capabilities','profiles','lenses','outputSchemas'}: print('PROFILE_UNKNOWN_PROPERTY'); raise SystemExit(1)
if p.get('schemaVersion') != 2 or set(p.get('capabilities',[]))!=allowed: print('PROFILE_SCHEMA_INVALID'); raise SystemExit(1)
if not isinstance(p['lenses'],dict) or not p['lenses']: print('PROFILE_REGISTRY_INVALID'); raise SystemExit(1)
if not isinstance(p['outputSchemas'],dict) or not p['outputSchemas']: print('PROFILE_OUTPUT_SCHEMAS_INVALID'); raise SystemExit(1)
for n,v in p['profiles'].items():
 if set(v)!={'role','capabilities','tiers','models','escalation','maxAttempts'} or v['role'] not in ('architect','worker','reviewer','merge','explorer'): print('PROFILE_CAPABILITY_INVALID',n); raise SystemExit(1)
 if not set(v['capabilities'])<=allowed or len(v['capabilities'])!=len(set(v['capabilities'])) or not 1<=v['maxAttempts']<=3: print('PROFILE_CAPABILITY_INVALID',n); raise SystemExit(1)
 if set(v['tiers'])!=set(v['models']) or len(v['tiers'])!=len(set(v['tiers'])): print('PROFILE_TIER_MAPPING_INVALID',n); raise SystemExit(1)
 for a,b in v['escalation'].items():
  if a not in v['tiers'] or b not in v['tiers'] or a==b: print('PROFILE_ESCALATION_INVALID',n); raise SystemExit(1)
print('PROFILE_OK')
PY
}
job_validate_dag() {
 local file="${1:-}"; [ -f "$file" ] || { echo DAG_INPUT_MISSING; return 1; }; job_json_unique_keys "$file" || { echo DAG_DUPLICATE_KEY; return 1; }; job_validate_profiles >/dev/null || return 1
 python3 - "$file" "$job_profiles_file" <<'PY'
import json,sys,re
x=json.load(open(sys.argv[1])); p=json.load(open(sys.argv[2])); j=x.get('jobs',[]); ids=[a.get('id') for a in j]
if set(x)!= {'schemaVersion','jobs'} or x['schemaVersion']!=2 or not 1<=len(j)<=16 or len(set(ids))!=len(ids): print('DAG_SCHEMA_INVALID'); raise SystemExit(1)
for a in j:
 if not isinstance(a,dict) or set(a)!={'id','role','profile','modelTier','dependsOn','writeScope','verify','lenses'}: print('DAG_UNKNOWN_PROPERTY'); raise SystemExit(1)
 if a['role'] not in ('architect','worker','reviewer','merge','explorer') or not re.fullmatch(r'[a-z][a-z0-9-]{0,62}',a['id']): print('DAG_JOB_INVALID',a.get('id')); raise SystemExit(1)
 q=p['profiles'].get(a['profile']);
 if not q or q['role'] != a['role'] or a['modelTier'] not in q['tiers']: print('ROUTE_INVALID',a['id']); raise SystemExit(1)
 if len(a['dependsOn'])!=len(set(a['dependsOn'])) or len(a['dependsOn'])>15: print('DAG_DEPENDENCY_INVALID',a['id']); raise SystemExit(1)
 for i,d in enumerate(a['dependsOn']):
  if d not in ids: print('DAG_DEPENDENCY_INVALID',a['id']); raise SystemExit(1)
  if d==a['id']: print(f'DAG_SELF_DEPENDENCY job={a["id"]} path=dependsOn[{i}]'); raise SystemExit(1)
 s=a['writeScope']
 if not isinstance(s,list) or not s or len(s)>64 or len(s)!=len(set(s)): print('SCOPE_INVALID',a['id']); raise SystemExit(1)
 for z in s:
  if not isinstance(z,str) or not z or z.startswith('/') or z.endswith('/') or '//' in z or '\\' in z or any(k in ('.','..','') for k in z.split('/')): print('SCOPE_INVALID_PATH',z); raise SystemExit(1)
 if not isinstance(a['verify'],str) or not a['verify'] or not isinstance(a['lenses'],list) or not 1<=len(a['lenses'])<=8 or len(a['lenses'])!=len(set(a['lenses'])) or any(l not in p['lenses'] for l in a['lenses']): print('DAG_REQUIRED_INVALID',a['id']); raise SystemExit(1)
by={a['id']:a for a in j}; state={}; stack=[]
def dfs(n):
 state[n]=1; stack.append(n)
 for d in by[n]['dependsOn']:
  if state.get(d)==1: print('DAG_CYCLE path='+'->'.join(stack[stack.index(d):]+[d])); raise SystemExit(1)
  if not state.get(d): dfs(d)
 stack.pop(); state[n]=2
for n in sorted(ids):
 if not state.get(n): dfs(n)
for i,a in enumerate(j):
 for b in j[i+1:]:
  for z in a['writeScope']:
   for y in b['writeScope']:
    if z==y or z.startswith(y+'/') or y.startswith(z+'/'): print(f'CROSS_JOB_SCOPE_OVERLAP jobs={a["id"]},{b["id"]} paths={z},{y}'); raise SystemExit(1)
print('DAG_OK')
PY
}
job_route_model() { local profile=$1 tier=$2; python3 - "$job_profiles_file" "$profile" "$tier" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); q=p['profiles'].get(sys.argv[2]);
if not q or sys.argv[3] not in q['models']: print('ROUTE_INVALID'); raise SystemExit(1)
print(q['models'][sys.argv[3]])
PY
}
job_assignments_to_dag() {
 local steps_json=$1 output=$2
 python3 - "$steps_json" "$output" "$job_framework_root" <<'PY'
import hashlib,json,os,sys,tempfile
steps,out,root=sys.argv[1:]
try: rows=json.load(open(steps,encoding='utf8'))
except Exception: print('BRIDGE_INPUT_INVALID',file=sys.stderr); raise SystemExit(1)
if not isinstance(rows,list) or not rows: print('BRIDGE_STEPS_EMPTY',file=sys.stderr); raise SystemExit(1)
allowed_files=set()
for line in open(os.path.join(root,'.gitignore'),encoding='utf8') if os.path.isfile(os.path.join(root,'.gitignore')) else []: pass
jobs=[]; seen=set()
tracked=set()
try:
 tracked={x.strip() for x in os.popen("git -C %s ls-files" % __import__('shlex').quote(root)).read().splitlines()}
except Exception: tracked=set()
for row in rows:
 if not isinstance(row,dict) or row.get('role')!='worker': print('BRIDGE_ROLE_INVALID',file=sys.stderr); raise SystemExit(1)
 required=('id','profile','modelTier','dependsOn','writeScope','verify','lenses')
 if any(k not in row or row[k] is None or row[k]=='' for k in required): print('BRIDGE_FIELD_MISSING',file=sys.stderr); raise SystemExit(1)
 if row['id'] in seen: print('BRIDGE_DUPLICATE_ID',file=sys.stderr); raise SystemExit(1)
 seen.add(row['id'])
 for p in row['writeScope']:
  if not isinstance(p,str) or p.startswith('/') or p.startswith('../') or '/..' in p or p not in tracked: print('BRIDGE_UNKNOWN_FILE' if p not in tracked else 'BRIDGE_SCOPE_INVALID',file=sys.stderr); raise SystemExit(1)
 jobs.append({k:row[k] for k in ('id','role','profile','modelTier','dependsOn','writeScope','verify','lenses')})
obj={'schemaVersion':2,'jobs':jobs}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(out) or '.',prefix='.bridge.',text=True)
with os.fdopen(fd,'w',encoding='utf8') as f: json.dump(obj,f,separators=(',',':'),sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
# Validate the staged artifact before publishing it.
try:
 check=json.load(open(tmp,encoding='utf8')); js=check['jobs']
 if check.get('schemaVersion') != 2 or not 1 <= len(js) <= 16: raise ValueError('DAG_SCHEMA_INVALID')
 ids={j['id'] for j in js}
 if len(ids) != len(js): raise ValueError('DAG_DUPLICATE_ID')
 for j in js:
  if set(j) != {'id','role','profile','modelTier','dependsOn','writeScope','verify','lenses'}: raise ValueError('DAG_UNKNOWN_PROPERTY')
  if j['role'] != 'worker' or any(d not in ids or d == j['id'] for d in j['dependsOn']):
   if j['dependsOn']: raise ValueError('DAG_DEPENDENCY_INVALID')
  if not j['writeScope'] or len(j['writeScope']) != len(set(j['writeScope'])): raise ValueError('SCOPE_INVALID')
  q=json.load(open(os.path.join(root,'templates/job-profiles.json'),encoding='utf8'))['profiles'].get(j['profile'])
  if not q or j['modelTier'] not in q['tiers'] or not j['verify'] or not j['lenses']:
   raise ValueError('DAG_REQUIRED_INVALID')
except Exception as e:
 os.unlink(tmp); print(str(e),file=sys.stderr); raise SystemExit(1)
# Validate the published shape with the canonical runtime validator before replacement.
import subprocess
if subprocess.run(['bash','-c','source '+__import__('shlex').quote(os.path.join(root,'lib/job-framework.sh'))+'; job_validate_dag "$1"', 'bridge', tmp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
 os.unlink(tmp); print('DAG_VALIDATION_FAILED',file=sys.stderr); raise SystemExit(1)
os.replace(tmp,out)
print('DAG_ASSIGNMENTS_OK')
PY
}

job_context_validate() {
 local context=$1 root=$2 worktree=$3 base_sha=$4
 python3 - "$context" "$root" "$worktree" "$base_sha" <<'PY'
import json,os,sys
p,root,wt,base=sys.argv[1:]
keys='jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId baseSha repositoryRoot worktreePath'.split()
try: c=json.load(open(p))
except Exception: print('JOB_CONTEXT_INVALID field=json',file=sys.stderr); raise SystemExit(1)
for k in keys:
 if k not in c: print('JOB_CONTEXT_INVALID field='+k,file=sys.stderr); raise SystemExit(1)
if set(c)!=set(keys): print('JOB_CONTEXT_INVALID field=keys',file=sys.stderr); raise SystemExit(1)
checks=[('repositoryRoot',os.path.realpath(root),os.path.realpath(c['repositoryRoot'])),('worktreePath',os.path.realpath(wt),os.path.realpath(c['worktreePath'])),('baseSha',base,c['baseSha'])]
for field,a,b in checks:
 if a!=b: print('JOB_CONTEXT_INVALID field='+field,file=sys.stderr); raise SystemExit(1)
try:
 model=json.load(open(os.path.join(root,'templates/job-profiles.json')))['profiles'][c['profile']]['models'][c['modelTier']]
except Exception: print('JOB_CONTEXT_INVALID field=modelId',file=sys.stderr); raise SystemExit(1)
if c['modelId']!=model: print('JOB_CONTEXT_INVALID field=modelId',file=sys.stderr); raise SystemExit(1)
print('JOB_CONTEXT_OK')
PY
}
job_default_adapter() { local context=$1; [ -f "$context" ]; }
job_adapter_new() {
 local callback=${1:-}
 [ -n "$callback" ] && declare -F "$callback" >/dev/null || { echo 'ADAPTER_INVALID construction' >&2; return 1; }
 JOB_ADAPTER_CALLBACK=$callback
}
job_adapter_dispatch() {
 local context=$1
 [ -f "$context" ] || { echo 'JOB_CONTEXT_INVALID field=file' >&2; return 1; }
 local root wt base
 root=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["repositoryRoot"])' "$context") || return 1
 wt=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["worktreePath"])' "$context") || return 1
 base=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["baseSha"])' "$context") || return 1
 job_context_validate "$context" "$root" "$wt" "$base" || return 1
 "$JOB_ADAPTER_CALLBACK" "$context"
 rm -f "$context"
}

job_context_create() {
 local dag=$1 job=$2 runid=$3 dispatchid=$4 root=$5 worktree=$6 out=$7 correlation=${8:-}
 python3 - "$dag" "$job" "$runid" "$dispatchid" "$root" "$worktree" "$out" <<'PY'
import json,os,sys,tempfile,subprocess
p,jid,run,did,root,wt,out=sys.argv[1:]
d=json.load(open(p)); rec=next((x for x in d['jobs'] if x['id']==jid),None)
if not rec: print('JOB_CONTEXT_INVALID field=jobId',file=sys.stderr); raise SystemExit(1)
model=json.load(open(os.path.join(root,'templates/job-profiles.json')))['profiles'][rec['profile']]['models'][rec['modelTier']]
ctx={'jobId':jid,'role':rec['role'],'profile':rec['profile'],'modelTier':rec['modelTier'],'modelId':model,'dependsOn':rec['dependsOn'],'writeScope':rec['writeScope'],'verify':rec['verify'],'lenses':rec['lenses'],'runId':run,'dispatchId':did,'baseSha':subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip(),'repositoryRoot':os.path.realpath(root),'worktreePath':os.path.realpath(wt)}
if set(ctx)!=set('jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId baseSha repositoryRoot worktreePath'.split()): print('JOB_CONTEXT_INVALID field=keys',file=sys.stderr); raise SystemExit(1)
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(out) or '.',prefix='.context.',text=True)
with os.fdopen(fd,'w') as f: json.dump(ctx,f,separators=(',',':'),sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
os.replace(tmp,out)
PY
}

job_orchestrate() {
 local goal=$1 assignments=$2 root=${3:-$job_framework_root} runid=${4:-orchestrator-$(date -u +%Y%m%dT%H%M%SZ)}
 [ -n "$goal" ] && [ -f "$assignments" ] || { echo 'ORCHESTRATOR_INPUT_INVALID' >&2; return 1; }
 local count tmp; count=$(python3 - "$assignments" <<'PY'
import json,sys
try: x=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(1)
if not isinstance(x,list) or not x: raise SystemExit(1)
print(len(x))
PY
) || { echo 'ORCHESTRATOR_INPUT_INVALID' >&2; return 1; }
 if [ "$count" -eq 1 ]; then
  tmp=$(mktemp); job_assignments_to_dag "$assignments" "$tmp" >/dev/null || { rm -f "$tmp"; return 1; }
  job_validate_dag "$tmp" >/dev/null || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  printf 'ORCHESTRATOR_ROUTE direct\n'
  return 0
 fi
 local run="$root/.loops/runs/$runid"; mkdir -p "$run"
 job_assignments_to_dag "$assignments" "$run/job-dag.json" >/dev/null || return 1
 job_validate_dag "$run/job-dag.json" >/dev/null || return 1
 printf 'ORCHESTRATOR_ROUTE dag\n%s\n' "$run/job-dag.json"
}

job_schedule() { local file=$1; job_validate_dag "$file" >/dev/null || return 1; python3 - "$file" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))['jobs']; done=set()
while len(done)<len(j):
 r=sorted(a['id'] for a in j if a['id'] not in done and set(a['dependsOn'])<=done)
 if not r: print('DAG_CYCLE'); raise SystemExit(1)
 print(*r,sep='\n'); done.update(r)
PY
}
job_scope_check() { local wt=$1 base=$2 allowed_csv=$3; [ -n "$wt" ]&&[ -n "$base" ]&&[ -n "$allowed_csv" ]||return 1; local allow="|$allowed_csv|" out=''; while IFS= read -r path; do [ -n "$path" ]||continue; case "$allow" in *"|$path|"*) ;; *)out+="$path\n";;esac; done < <({ git -C "$wt" diff --name-only --no-renames "$base" HEAD; git -C "$wt" diff --name-only --no-renames; git -C "$wt" diff --cached --name-only --no-renames; git -C "$wt" ls-files --others --exclude-standard; }|sort -u); [ -z "$out" ]||{ printf '%b' "$out"|sort -u; return 1; }; }
job_atomic_write() { local file=$1 data=$2; mkdir -p "$(dirname "$file")"; local t="$file.tmp.$$"; printf '%s\n' "$data">"$t"; mv -f "$t" "$file"; }

job_runtime_set_worktree() { python3 - "$1" "$2" "$3" <<'PY'
import json,os,sys,tempfile
p,j,w=sys.argv; d=json.load(open(p)); d['jobs'][j]['worktree']=w
fd,t=tempfile.mkstemp(dir=os.path.dirname(p),prefix='.jobs.',text=True)
with os.fdopen(fd,'w') as f: json.dump(d,f,separators=(',',':')); f.flush(); os.fsync(f.fileno())
os.replace(t,p)
PY
}
# Worker output is review evidence. The runtime does not require report envelopes.
# The architect owns contract semantics and decides acceptance outside this executor.
job_review_plan() {
 local dag=$1 job=$2
 python3 - "$dag" "$job" <<'PY'
import json,sys
jobs={j['id']:j for j in json.load(open(sys.argv[1]))['jobs']}
j=jobs.get(sys.argv[2])
if not j: raise SystemExit('JOB_UNKNOWN')
for lens in sorted(j['lenses']): print(lens)
PY
}

job_reconcile() {
 local ledger=$1 root=${2:-$(git rev-parse --show-toplevel)}
 job_executor_reconcile "$ledger" "$root"
}
job_run() {
 local dag=$1 runid=${2:-$(date -u +%Y%m%dT%H%M%SZ)} root run_dir ledger base
 [ -f "$dag" ] || { echo DAG_INPUT_MISSING >&2; return 1; }
 root=$(git rev-parse --show-toplevel) || return 1
 job_validate_dag "$dag" >/dev/null || return 1
 run_dir=$(job_executor_init "$root" "$runid" "$dag") || return 1
 ledger=$run_dir/jobs.json; base=$(job_lifecycle_ledger_read "$ledger" "d['baseSha']")
 trap 'job_executor_release_lock' RETURN
 while :; do
  local ready=() jid wt ctx item rc=0 pids=()
  while IFS=$'\t' read -r jid state; do [ "$state" = ready ] && ready+=("$jid"); done < <(job_lifecycle_ready "$ledger")
  [ "${#ready[@]}" -gt 0 ] || break
  for jid in "${ready[@]}"; do
   wt=$(job_executor_worktree_create "$root" "$runid" "$jid" "$base" | awk -F '\t' '{print $2}') || return 1
   job_runtime_set_worktree "$ledger" "$jid" "$wt"; job_executor_transition "$ledger" "$jid" ready >/dev/null; job_executor_transition "$ledger" "$jid" running >/dev/null
   ctx="$run_dir/$jid.context.json"; job_context_create "$dag" "$jid" "$runid" "dispatch-$jid" "$root" "$wt" "$ctx"; job_adapter_dispatch "$ctx" & pids+=("$!:$jid")
  done
  for item in "${pids[@]}"; do jid=${item#*:}; if wait "${item%%:*}" && job_lifecycle_scope_gate "$ledger" "$jid"; then job_executor_transition "$ledger" "$jid" passed >/dev/null; job_review_plan "$dag" "$jid" > "$run_dir/$jid.review-lenses"; else job_executor_transition "$ledger" "$jid" failed >/dev/null 2>&1 || true; job_lifecycle_block_dependents "$ledger" "$jid" >/dev/null || true; rc=1; fi; done
  [ "$rc" -eq 0 ] || return "$rc"
 done
 printf 'RUN_RECONCILIATION_READY %s\n' "$ledger"
}
