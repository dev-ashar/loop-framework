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
if p.get('schemaVersion')!=1 or set(p.get('capabilities',[]))!=allowed: print('PROFILE_SCHEMA_INVALID'); raise SystemExit(1)
if not isinstance(p['lenses'],dict) or not p['lenses']: print('PROFILE_REGISTRY_INVALID'); raise SystemExit(1)
if set(p['outputSchemas'])!={'exploration-report','contract-proposal','builder-report','evaluator-report'}: print('PROFILE_OUTPUT_SCHEMAS_INVALID'); raise SystemExit(1)
for n,v in p['profiles'].items():
 if set(v)!={'role','capabilities','tiers','models','escalation','maxAttempts'} or v['role']!='builder': print('PROFILE_CAPABILITY_INVALID',n); raise SystemExit(1)
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
if set(x)!= {'schemaVersion','jobs'} or x['schemaVersion']!=1 or not 1<=len(j)<=16 or len(set(ids))!=len(ids): print('DAG_SCHEMA_INVALID'); raise SystemExit(1)
for a in j:
 if not isinstance(a,dict) or set(a)!={'id','role','profile','modelTier','dependsOn','writeScope','verify','lenses'}: print('DAG_UNKNOWN_PROPERTY'); raise SystemExit(1)
 if a['role']!='builder' or not re.fullmatch(r'[a-z][a-z0-9-]{0,62}',a['id']): print('DAG_JOB_INVALID',a.get('id')); raise SystemExit(1)
 q=p['profiles'].get(a['profile']);
 if not q or a['modelTier'] not in q['tiers']: print('ROUTE_INVALID',a['id']); raise SystemExit(1)
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
job_contract_bridge() {
 local contract_path=$1 steps_json=$2 output=$3 expected_hash=${4:-}
 python3 - "$contract_path" "$steps_json" "$output" "$expected_hash" "$job_framework_root" <<'PY'
import hashlib,json,os,sys,tempfile
contract,steps,out,expected,root=sys.argv[1:]
if not os.path.isfile(contract): print('CONTRACT_INPUT_MISSING',file=sys.stderr); raise SystemExit(1)
actual=hashlib.sha256(open(contract,'rb').read()).hexdigest()
if expected and expected!=actual: print('STALE_CONTRACT_HASH',file=sys.stderr); raise SystemExit(1)
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
 if not isinstance(row,dict) or row.get('role')!='builder': print('BRIDGE_ROLE_INVALID',file=sys.stderr); raise SystemExit(1)
 required=('id','profile','modelTier','dependsOn','writeScope','verify','lenses')
 if any(k not in row or row[k] is None or row[k]=='' for k in required): print('BRIDGE_FIELD_MISSING',file=sys.stderr); raise SystemExit(1)
 if row['id'] in seen: print('BRIDGE_DUPLICATE_ID',file=sys.stderr); raise SystemExit(1)
 seen.add(row['id'])
 for p in row['writeScope']:
  if not isinstance(p,str) or p.startswith('/') or p.startswith('../') or '/..' in p or p not in tracked: print('BRIDGE_UNKNOWN_FILE' if p not in tracked else 'BRIDGE_SCOPE_INVALID',file=sys.stderr); raise SystemExit(1)
 jobs.append({k:row[k] for k in ('id','role','profile','modelTier','dependsOn','writeScope','verify','lenses')})
obj={'schemaVersion':1,'jobs':jobs}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(out) or '.',prefix='.bridge.',text=True)
with os.fdopen(fd,'w',encoding='utf8') as f: json.dump(obj,f,separators=(',',':'),sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
# Validate the staged artifact before publishing it.
try:
 check=json.load(open(tmp,encoding='utf8')); js=check['jobs']
 if check.get('schemaVersion') != 1 or not 1 <= len(js) <= 16: raise ValueError('DAG_SCHEMA_INVALID')
 ids={j['id'] for j in js}
 if len(ids) != len(js): raise ValueError('DAG_DUPLICATE_ID')
 for j in js:
  if set(j) != {'id','role','profile','modelTier','dependsOn','writeScope','verify','lenses'}: raise ValueError('DAG_UNKNOWN_PROPERTY')
  if j['role'] != 'builder' or not j['dependsOn'] or any(d not in ids or d == j['id'] for d in j['dependsOn']):
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
meta=out+'.metadata.json'
fd,mt=tempfile.mkstemp(dir=os.path.dirname(meta) or '.',prefix='.bridge-meta.',text=True)
with os.fdopen(fd,'w',encoding='utf8') as f:
 json.dump({'schemaVersion':1,'contractHash':actual,'dagSha256':hashlib.sha256(open(out,'rb').read()).hexdigest()},f,separators=(',',':')); f.write('\n'); f.flush(); os.fsync(f.fileno())
os.replace(mt,meta)
print('DAG_BRIDGE_OK contractHash='+actual)
PY
}

job_bridge_metadata_validate() {
 local dag=$1 metadata=$2 contract_path=$3
 python3 - "$dag" "$metadata" "$contract_path" <<'PY'
import hashlib,json,sys,os
dag,meta,contract=sys.argv[1:]
try:
 d=json.load(open(dag)); m=json.load(open(meta))
except Exception: print('BRIDGE_METADATA_INVALID field=json',file=sys.stderr); raise SystemExit(1)
actual_contract=hashlib.sha256(open(contract,'rb').read()).hexdigest()
actual_dag=hashlib.sha256(open(dag,'rb').read()).hexdigest()
if list(m)!=['schemaVersion','contractHash','dagSha256'] or m.get('schemaVersion')!=1: print('BRIDGE_METADATA_INVALID field=shape',file=sys.stderr); raise SystemExit(1)
if m.get('contractHash')!=actual_contract: print('BRIDGE_METADATA_INVALID field=contractHash',file=sys.stderr); raise SystemExit(1)
if m.get('dagSha256')!=actual_dag: print('BRIDGE_METADATA_INVALID field=dagSha256',file=sys.stderr); raise SystemExit(1)
print('BRIDGE_METADATA_OK')
PY
}

job_context_validate() {
 local context=$1 root=$2 worktree=$3 contract_hash=$4 base_sha=$5
 python3 - "$context" "$root" "$worktree" "$contract_hash" "$base_sha" <<'PY'
import hashlib,json,os,subprocess,sys
p,root,wt,ch,base=sys.argv[1:]
keys='jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId contractHash baseSha repositoryRoot worktreePath'.split()
try: c=json.load(open(p))
except Exception: print('JOB_CONTEXT_INVALID field=json',file=sys.stderr); raise SystemExit(1)
for k in keys:
 if k not in c: print('JOB_CONTEXT_INVALID field='+k,file=sys.stderr); raise SystemExit(1)
if set(c)!=set(keys): print('JOB_CONTEXT_INVALID field=keys',file=sys.stderr); raise SystemExit(1)
checks=[('repositoryRoot',os.path.realpath(root),os.path.realpath(c['repositoryRoot'])),('worktreePath',os.path.realpath(wt),os.path.realpath(c['worktreePath'])),('contractHash',ch,c['contractHash']),('baseSha',base,c['baseSha'])]
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
 local root wt ch base
 root=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["repositoryRoot"])' "$context") || return 1
 wt=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["worktreePath"])' "$context") || return 1
 ch=$(sha256sum "$job_framework_root/.loops/contract.md"|awk '{print $1}'); base=$(git -C "$root" rev-parse HEAD) || return 1
 job_context_validate "$context" "$root" "$wt" "$ch" "$base" || return 1
 "$JOB_ADAPTER_CALLBACK" "$context"
 rm -f "$context"
}

job_context_create() {
 local dag=$1 job=$2 runid=$3 dispatchid=$4 root=$5 worktree=$6 out=$7 correlation=${8:-}
 python3 - "$dag" "$job" "$runid" "$dispatchid" "$root" "$worktree" "$out" "$job_framework_root/.loops/contract.md" <<'PY'
import hashlib,json,os,sys,tempfile,subprocess
p,jid,run,did,root,wt,out,contract=sys.argv[1:]
d=json.load(open(p)); rec=next((x for x in d['jobs'] if x['id']==jid),None)
if not rec: print('JOB_CONTEXT_INVALID field=jobId',file=sys.stderr); raise SystemExit(1)
model=json.load(open(os.path.join(root,'templates/job-profiles.json')))['profiles'][rec['profile']]['models'][rec['modelTier']]
ctx={'jobId':jid,'role':rec['role'],'profile':rec['profile'],'modelTier':rec['modelTier'],'modelId':model,'dependsOn':rec['dependsOn'],'writeScope':rec['writeScope'],'verify':rec['verify'],'lenses':rec['lenses'],'runId':run,'dispatchId':did,'contractHash':hashlib.sha256(open(contract,'rb').read()).hexdigest(),'baseSha':subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip(),'repositoryRoot':os.path.realpath(root),'worktreePath':os.path.realpath(wt)}
if set(ctx)!=set('jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId contractHash baseSha repositoryRoot worktreePath'.split()): print('JOB_CONTEXT_INVALID field=keys',file=sys.stderr); raise SystemExit(1)
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(out) or '.',prefix='.context.',text=True)
with os.fdopen(fd,'w') as f: json.dump(ctx,f,separators=(',',':'),sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
os.replace(tmp,out)
PY
}

job_orchestrate() {
 local goal=$1 planner_steps=$2 root=${3:-$job_framework_root} runid=${4:-orchestrator-$(date -u +%Y%m%dT%H%M%SZ)}
 [ -n "$goal" ] && [ -f "$planner_steps" ] || { echo 'ORCHESTRATOR_INPUT_INVALID' >&2; return 1; }
 local count; count=$(python3 - "$planner_steps" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); print(len(x) if isinstance(x,list) else 0)
PY
)
 if [ "$count" -le 1 ]; then
  printf 'ORCHESTRATOR_ROUTE legacy\n'
  return 0
 fi
 local run="$root/.loops/runs/$runid"; mkdir -p "$run"
 local hash; hash=$(sha256sum "$root/.loops/contract.md"|awk '{print $1}')
 job_contract_bridge "$root/.loops/contract.md" "$planner_steps" "$run/job-dag.json" "$hash" >/dev/null || return 1
 job_bridge_metadata_validate "$run/job-dag.json" "$run/job-dag.json.metadata.json" "$root/.loops/contract.md" >/dev/null || return 1
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
job_runtime_validate_builder() { local r=$1 c=$2 u=$3 t=$4 h=$5; bash "$job_framework_root/.loops/verify.sh" agent-envelope "$r" --correlation "$c" --run "$u" --role builder --task "$t" --contract "$h" && bash "$job_framework_root/.loops/verify.sh" builder-report "$r"; }
job_runtime_validate_evaluator() { local r=$1 c=$2 u=$3 t=$4 h=$5; bash "$job_framework_root/.loops/verify.sh" agent-envelope "$r" --correlation "$c" --run "$u" --role evaluator --task "$t" --contract "$h" || return 1; python3 - "$r" <<'PY'
s=open(__import__('sys').argv[1],encoding='utf8').read().splitlines()[1:]
raise SystemExit(0 if all(any(k in x for x in s) for k in ('REVIEW','SCORE','CRITERIA','GAP','CHECKS RUN')) else 1)
PY
}
job_run() {
 local dag=$1 runid=${2:-$(date -u +%Y%m%dT%H%M%SZ)} root run_dir ledger base; local correlation=${JOB_CORRELATION_ID:-$runid} contract task
 [ -f "$dag" ]||{ echo DAG_INPUT_MISSING >&2; return 1; }; root=$(git rev-parse --show-toplevel)||return 1; job_validate_dag "$dag" >/dev/null||return 1
 contract=$(sha256sum "$root/.loops/contract.md"|awk '{print $1}'); task=$(sha256sum "$dag"|awk '{print $1}'); run_dir=$(job_executor_init "$root" "$runid" "$dag")||return 1; ledger=$run_dir/jobs.json; base=$(job_lifecycle_ledger_read "$ledger" "d['baseSha']"); trap 'job_executor_release_lock' RETURN
 while :; do
  ready=(); while IFS=$'\t' read -r jid state; do [ "$state" = ready ] && ready+=("$jid"); done < <(job_lifecycle_ready "$ledger")
  [ "${#ready[@]}" -gt 0 ]||break; local pids=() jid wt
  for jid in "${ready[@]}"; do wt=$(job_executor_worktree_create "$root" "$runid" "$jid" "$base"|awk -F '\t' '{print $2}')||return 1; job_runtime_set_worktree "$ledger" "$jid" "$wt"; job_approval_observe "$root" "$contract" "$runid" "$correlation" builder||return 1; job_executor_transition "$ledger" "$jid" ready >/dev/null; job_executor_transition "$ledger" "$jid" running >/dev/null; ctx="$run_dir/$jid.context.json"; job_context_create "$dag" "$jid" "$runid" "dispatch-$jid" "$root" "$wt" "$ctx"; job_adapter_dispatch "$ctx" & pids+=("$!:$jid"); done
 local item rc=0; for item in "${pids[@]}"; do jid=${item#*:}; if wait "${item%%:*}"; then job_executor_transition "$ledger" "$jid" passed >/dev/null; job_lifecycle_integrate_job "$ledger" "$root" "$runid" "$jid" >/dev/null||rc=1; else job_executor_transition "$ledger" "$jid" failed >/dev/null||rc=1; job_lifecycle_block_dependents "$ledger" "$jid" >/dev/null||true; fi; done; [ "$rc" -eq 0 ]||return "$rc"; done
 printf 'RUN_LEDGER_CREATED %s\n' "$ledger"
}
