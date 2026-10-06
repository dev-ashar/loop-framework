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
 local file="${1:-$job_profiles_file}"; local agents_dir="${LOOPS_AGENTS_DIR:-$(cd "$(dirname "$file")/.." && pwd)/.claude/agents}"
 job_json_unique_keys "$file" || { echo PROFILE_DUPLICATE_KEY; return 1; }
 python3 - "$file" "$agents_dir" <<'PY'
import json,os,re,sys
p=json.load(open(sys.argv[1],encoding='utf8')); agents=sys.argv[2]
allowed={'read-source','write-source','run-tests','git-read','git-worktree','memory-read','memory-write'}
if set(p)!= {'schemaVersion','modelRegistry','projections','capabilities','profiles','lenses','outputSchemas'}: print('PROFILE_UNKNOWN_PROPERTY'); raise SystemExit(1)
if p.get('schemaVersion') != 3 or set(p.get('capabilities',[]))!=allowed: print('PROFILE_SCHEMA_INVALID'); raise SystemExit(1)
for m,v in p.get('modelRegistry',{}).items():
 if v.get('provider')!='haip' or v.get('lifecycle') not in ('active','trial','candidate','retired') or not isinstance(v.get('roles'),list) or not isinstance(v.get('efforts',[]),list) or not isinstance(v.get('routes',[]),list): print('MODEL_REGISTRY_INVALID',m); raise SystemExit(1)
if not isinstance(p['lenses'],dict) or not p['lenses']: print('PROFILE_REGISTRY_INVALID'); raise SystemExit(1)
if not isinstance(p['outputSchemas'],dict) or not p['outputSchemas']: print('PROFILE_OUTPUT_SCHEMAS_INVALID'); raise SystemExit(1)
for n,v in p['profiles'].items():
 if set(v)!={'role','capabilities','tiers','models','effort','escalation','maxAttempts'} or v['role'] not in ('architect','planner','worker','reviewer','merge','explorer'): print('PROFILE_CAPABILITY_INVALID',n); raise SystemExit(1)
 if not set(v['capabilities'])<=allowed or len(v['capabilities'])!=len(set(v['capabilities'])) or not 1<=v['maxAttempts']<=3: print('PROFILE_CAPABILITY_INVALID',n); raise SystemExit(1)
 if set(v['tiers'])!=set(v['models']) or len(v['tiers'])!=len(set(v['tiers'])) or set(v.get('effort',{}))!=set(v['tiers']): print('PROFILE_TIER_MAPPING_INVALID',n); raise SystemExit(1)
 if v['role']=='reviewer' and 'write-source' in v['capabilities']: print('REVIEWER_WRITE_SOURCE_FORBIDDEN',n); raise SystemExit(1)
 for tier,model in v['models'].items():
  r=p['modelRegistry'].get(model)
  if not r or r['lifecycle'] not in ('active','trial') or v['role'] not in r['roles'] or v['effort'][tier] not in r['efforts'] or {'profile':n,'tier':tier} not in r['routes']: print('ROUTE_REGISTRY_INVALID',n,tier); raise SystemExit(1)
 for a,b in v['escalation'].items():
  if a not in v['tiers'] or b not in v['tiers'] or a==b: print('PROFILE_ESCALATION_INVALID',n); raise SystemExit(1)
for role,projection in p.get('projections',{}).items():
 q=p['profiles'].get(projection.get('profile'))
 if not q or q['role']!=role or projection.get('tier') not in q['tiers']: print('PROJECTION_INVALID',role); raise SystemExit(1)
 path=os.path.join(agents,role+'.md')
 try: lines=open(path,encoding='utf8').read().splitlines()
 except OSError: print('PROJECTION_FRONTMATTER_MISSING',role); raise SystemExit(1)
 if not lines or lines[0].strip()!='---': print('PROJECTION_FRONTMATTER_INVALID',role); raise SystemExit(1)
 try: end=next(i for i in range(1,len(lines)) if lines[i].strip()=='---')
 except StopIteration: print('PROJECTION_FRONTMATTER_INVALID',role); raise SystemExit(1)
 fields={}
 for line in lines[1:end]:
  m=re.match(r'^\s*([A-Za-z][A-Za-z0-9_-]*):\s*(.*?)\s*$',line)
  if m: fields[m.group(1)]=m.group(2)
 tier=projection['tier']; expected=q['models'][tier]; expected_effort=q['effort'][tier]
 if fields.get('name')!=role or fields.get('model')!=expected or fields.get('effort')!=expected_effort: print('PROJECTION_FRONTMATTER_INVALID',role); raise SystemExit(1)
print('PROFILE_OK')
PY
}
job_validate_dag() {
 local file="${1:-}"; [ -f "$file" ] || { echo DAG_INPUT_MISSING; return 1; }; job_json_unique_keys "$file" || { echo DAG_DUPLICATE_KEY; return 1; }; job_validate_profiles >/dev/null || return 1
 python3 - "$file" "$job_profiles_file" <<'PY'
import json,sys,re,os
x=json.load(open(sys.argv[1])); p=json.load(open(sys.argv[2])); j=x.get('jobs',[]); ids=[a.get('id') for a in j]
if set(x)!= {'schemaVersion','jobs'} or x['schemaVersion']!=2 or not 1<=len(j)<=16 or len(set(ids))!=len(ids): print('DAG_SCHEMA_INVALID'); raise SystemExit(1)
for a in j:
 allowed={"id","role","profile","modelTier","dependsOn","writeScope","readScope","objective","verify","lenses"}
 required={"id","role","profile","modelTier","dependsOn","writeScope","objective","verify","lenses"}
 if not isinstance(a,dict) or not required<=set(a) or not set(a)<=allowed: print("DAG_UNKNOWN_PROPERTY" if isinstance(a,dict) and set(a)-allowed else "DAG_REQUIRED_INVALID"); raise SystemExit(1)
 if a["role"] not in ("architect","planner","worker","reviewer","merge","explorer") or not re.fullmatch(r"[a-z][a-z0-9-]{0,62}",a["id"]): print("DAG_JOB_INVALID",a.get("id")); raise SystemExit(1)
 q=p["profiles"].get(a["profile"])
 if not q or q["role"] != a["role"] or a["modelTier"] not in q["tiers"]: print("ROUTE_INVALID",a["id"]); raise SystemExit(1)
 if len(a["dependsOn"])!=len(set(a["dependsOn"])) or len(a["dependsOn"])>15: print("DAG_DEPENDENCY_INVALID",a["id"]); raise SystemExit(1)
 for i,d in enumerate(a["dependsOn"]):
  if d not in ids: print("DAG_DEPENDENCY_INVALID",a["id"]); raise SystemExit(1)
  if d==a["id"]: print(f"DAG_SELF_DEPENDENCY job={a['id']} path=dependsOn[{i}]"); raise SystemExit(1)
 s=a["writeScope"]; read=a.get("readScope",[])
 if not isinstance(s,list) or len(s)>64 or len(s)!=len(set(s)): print("SCOPE_INVALID",a["id"]); raise SystemExit(1)
 if not isinstance(read,list) or len(read)>64 or len(read)!=len(set(read)): print("READ_SCOPE_INVALID",a["id"]); raise SystemExit(1)
 if a["role"]!="reviewer" and not s: print("SCOPE_INVALID",a["id"]); raise SystemExit(1)
 if a["role"]=="reviewer" and (s or not read): print("REVIEWER_SCOPE_INVALID",a["id"]); raise SystemExit(1)
 if a["role"]=="reviewer" and "write-source" in p["profiles"][a["profile"]]["capabilities"]: print("REVIEWER_WRITE_SOURCE_FORBIDDEN",a["id"]); raise SystemExit(1)
 for z in s+read:
  if not isinstance(z,str) or not z or z.startswith("/") or z.endswith("/") or "//" in z or "\\" in z or any(k in (".","..","") for k in z.split("/")): print("SCOPE_INVALID_PATH",z); raise SystemExit(1)
 if not isinstance(a["objective"],str) or not a["objective"] or a["objective"].strip()!=a["objective"] or len(a["objective"])>2048 or not isinstance(a["verify"],str) or not a["verify"] or not isinstance(a["lenses"],list) or not 1<=len(a["lenses"])<=8 or len(a["lenses"])!=len(set(a["lenses"])) or any(l not in p["lenses"] for l in a["lenses"]): print("DAG_REQUIRED_INVALID",a["id"]); raise SystemExit(1)
by={a['id']:a for a in j}; state={}; stack=[]
def dfs(n):
 state[n]=1; stack.append(n)
 for d in by[n]['dependsOn']:
  if state.get(d)==1: print('DAG_CYCLE path='+'->'.join(stack[stack.index(d):]+[d])); raise SystemExit(1)
  if not state.get(d): dfs(d)
 stack.pop(); state[n]=2
for n in sorted(ids):
 if not state.get(n): dfs(n)
if len(j)>1:
 for worker in [a for a in j if a['role']=='worker']:
  reviewers=[a for a in j if a['role']=='reviewer' and worker['id'] in a['dependsOn'] and 'write-source' not in p['profiles'][a['profile']]['capabilities']]
  if not reviewers: print('WORKER_REVIEWER_REQUIRED',worker['id']); raise SystemExit(1)
for reviewer in [a for a in j if a['role']=='reviewer']:
 if 'write-source' in p['profiles'][reviewer['profile']]['capabilities']: print('REVIEWER_WRITE_SOURCE_FORBIDDEN',reviewer['id']); raise SystemExit(1)
 if any(d==reviewer['id'] or by[d]['role']!='worker' for d in reviewer['dependsOn']): print('REVIEWER_DEPENDENCY_INVALID',reviewer['id']); raise SystemExit(1)
for i,a in enumerate(j):
 for b in j[i+1:]:
  for z in a.get('writeScope',[]):
   for y in b.get('writeScope',[]):
    if z==y or z.startswith(y+'/') or y.startswith(z+'/'): print(f'CROSS_JOB_SCOPE_OVERLAP jobs={a["id"]},{b["id"]} paths={z},{y}'); raise SystemExit(1)
print('DAG_OK')
PY
}
job_route_model() { local profile=$1 tier=$2; python3 - "$job_profiles_file" "$profile" "$tier" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); q=p['profiles'].get(sys.argv[2]);
if not q or sys.argv[3] not in q['models']: print('ROUTE_INVALID'); raise SystemExit(1)
m=q['models'][sys.argv[3]]; r=p['modelRegistry'].get(m)
if not r or r['provider']!='haip' or r['lifecycle'] not in ('active','trial') or {'profile':sys.argv[2],'tier':sys.argv[3]} not in r['routes']: print('ROUTE_INVALID'); raise SystemExit(1)
print(m)
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
if any(row.get('role')!='worker' for row in rows if isinstance(row,dict)):
 # Explicit DAGs may already contain read-only reviewers; preserve those jobs.
 if any(not isinstance(row,dict) or row.get('role') not in ('worker','reviewer') for row in rows): print('BRIDGE_ROLE_INVALID',file=sys.stderr); raise SystemExit(1)
allowed_files=set()
for line in open(os.path.join(root,'.gitignore'),encoding='utf8') if os.path.isfile(os.path.join(root,'.gitignore')) else []: pass
jobs=[]; seen=set()
tracked=set()
try:
 tracked={x.strip() for x in os.popen("git -C %s ls-files" % __import__('shlex').quote(root)).read().splitlines()}
except Exception: tracked=set()
for row in rows:
 if not isinstance(row,dict) or row.get('role') not in ('worker','reviewer'): print('BRIDGE_ROLE_INVALID',file=sys.stderr); raise SystemExit(1)
 if row.get('role')=='reviewer' and (row.get('profile')!='reviewer-default' or row.get('writeScope') or not row.get('readScope')): print('BRIDGE_REVIEWER_SCOPE_INVALID',file=sys.stderr); raise SystemExit(1)
 required=('id','profile','modelTier','dependsOn','writeScope','objective','verify','lenses')
 if any(k not in row or row[k] is None or row[k]=='' for k in required): print('BRIDGE_FIELD_MISSING',file=sys.stderr); raise SystemExit(1)
 if row['id'] in seen: print('BRIDGE_DUPLICATE_ID',file=sys.stderr); raise SystemExit(1)
 if not isinstance(row['objective'],str) or row['objective'].strip()!=row['objective'] or len(row['objective'])>2048: print('BRIDGE_OBJECTIVE_INVALID',file=sys.stderr); raise SystemExit(1)
 seen.add(row['id'])
 for p in row['writeScope']:
  if not isinstance(p,str) or p.startswith('/') or p.startswith('../') or '/..' in p or p not in tracked: print('BRIDGE_UNKNOWN_FILE' if p not in tracked else 'BRIDGE_SCOPE_INVALID',file=sys.stderr); raise SystemExit(1)
 job={k:row[k] for k in ('id','role','profile','modelTier','dependsOn','writeScope','objective','verify','lenses')}
 if row.get('role')=='reviewer': job['readScope']=row.get('readScope',[])
 jobs.append(job)
# Multi-job plans always receive a fresh, read-only downstream review job.
if len(rows)>1 and all(row.get('role')=='worker' for row in rows):
 for row in rows:
  rid='review-'+row['id']
  jobs.append({'id':rid,'role':'reviewer','profile':'reviewer-default','modelTier':'primary','dependsOn':[row['id']],'writeScope':[],'readScope':row['writeScope'],'objective':'Independently review '+row['objective'],'verify':'true','lenses':['correctness','scope']})
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
  if set(j) not in ({'id','role','profile','modelTier','dependsOn','writeScope','objective','verify','lenses'},{'id','role','profile','modelTier','dependsOn','writeScope','readScope','objective','verify','lenses'}): raise ValueError('DAG_UNKNOWN_PROPERTY')
  if any(d not in ids or d == j['id'] for d in j['dependsOn']): raise ValueError('DAG_DEPENDENCY_INVALID')
  if j['role']!='reviewer' and (not j['writeScope'] or len(j['writeScope']) != len(set(j['writeScope']))): raise ValueError('SCOPE_INVALID')
  if j['role']=='reviewer' and (j['writeScope'] or not j.get('readScope')): raise ValueError('REVIEWER_SCOPE_INVALID')
  q=json.load(open(os.path.join(root,'templates/job-profiles.json'),encoding='utf8'))['profiles'].get(j['profile'])
  if not q or j['modelTier'] not in q['tiers'] or not j['objective'] or j['objective'].strip()!=j['objective'] or len(j['objective'])>2048 or not j['verify'] or not j['lenses']:
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

job_context_trust_init() {
 local dag=$1 run_dir=$2 root=$3; local trust="$run_dir/context-trust.json"
 python3 - "$dag" "$run_dir" "$root" "$trust" "$job_profiles_file" <<'PY'
import hashlib,json,os,sys,tempfile
source,run_dir,root,out,profiles_path=sys.argv[1:]
source=os.path.realpath(source); root=os.path.realpath(root)
dag=json.load(open(source,encoding='utf8'))
ledger=json.load(open(os.path.join(run_dir,'jobs.json'),encoding='utf8'))
profiles=json.load(open(profiles_path,encoding='utf8'))
digest=hashlib.sha256(json.dumps(dag,sort_keys=True,separators=(',',':')).encode()).hexdigest()
trust={'version':1,'runId':ledger['runId'],'repositoryRoot':root,'baseSha':ledger['baseSha'],'dagPath':source,'dagDigest':digest,'jobs':{}}
for rec in dag['jobs']:
 entry=ledger['jobs'][rec['id']]
 prof=profiles.get('profiles',{}).get(rec['profile'])
 tier=rec.get('modelTier')
 model=prof and prof.get('models',{}).get(tier)
 info=profiles.get('modelRegistry',{}).get(model) if model else None
 effort=prof and prof.get('effort',{}).get(tier)
 if (not prof or not info or prof.get('role') != rec.get('role') or
     not model or not effort or info.get('lifecycle') not in ('active','trial') or
     rec.get('role') not in info.get('roles',[]) or effort not in info.get('efforts',[])):
  print('JOB_CONTEXT_TRUST_INVALID field=route',file=sys.stderr); raise SystemExit(1)
 trust['jobs'][rec['id']]={'jobId':rec['id'],'role':rec['role'],'profile':rec['profile'],'modelTier':rec['modelTier'],'modelId':model,'provider':info['provider'],'lifecycle':info['lifecycle'],'effort':effort,'dependsOn':rec['dependsOn'],'writeScope':rec['writeScope'],'readScope':rec.get('readScope',[]),'objective':rec['objective'],'verify':rec['verify'],'lenses':rec['lenses'],'status':entry.get('state','pending'),'worktreePath':entry.get('worktree','')}
fd,tmp=tempfile.mkstemp(dir=run_dir,prefix='.trust.',text=True)
with os.fdopen(fd,'w',encoding='utf8') as f:
 json.dump(trust,f,sort_keys=True,separators=(',',':')); f.write('\n'); f.flush(); os.fsync(f.fileno())
os.replace(tmp,out)
PY
}
job_context_trust_update() {
 local trust=$1 job=$2 worktree=$3 status=$4
 python3 - "$trust" "$job" "$worktree" "$status" <<'PY'
import json,os,sys,tempfile
p,jid,wt,status=sys.argv[1:]
d=json.load(open(p,encoding='utf8')); rec=d['jobs'].get(jid)
if not rec: raise SystemExit('JOB_CONTEXT_TRUST_INVALID')
rec['worktreePath']=os.path.realpath(wt); rec['status']=status
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(p),prefix='.trust.',text=True)
with os.fdopen(fd,'w',encoding='utf8') as f:
 json.dump(d,f,sort_keys=True,separators=(',',':')); f.write('\n'); f.flush(); os.fsync(f.fileno())
os.replace(tmp,p)
PY
}
job_context_validate() {
 local context=$1 root=$2 worktree=${3:-} base_sha=${4:-}
 python3 - "$context" "$root" "$worktree" "$base_sha" "$job_profiles_file" <<'PY'
import hashlib,json,os,sys
context,root,wt_arg,base_arg,profiles_path=sys.argv[1:]
root=os.path.realpath(root)
keys='jobId role profile modelTier modelId provider effort lifecycle status objective objectiveDigest dependsOn writeScope readScope verify lenses runId dispatchId baseSha dagPath dagDigest repositoryRoot worktreePath'.split()
try: c=json.load(open(context,encoding='utf8'))
except Exception: print('JOB_CONTEXT_INVALID field=json',file=sys.stderr); raise SystemExit(1)
if set(c)!=set(keys): print('JOB_CONTEXT_INVALID field=keys',file=sys.stderr); raise SystemExit(1)
trust_path=os.path.join(root,'.loops','runs',str(c.get('runId')),'context-trust.json')
try: trust=json.load(open(trust_path,encoding='utf8'))
except Exception: print('JOB_CONTEXT_INVALID field=trust',file=sys.stderr); raise SystemExit(1)
if trust.get('repositoryRoot') != root: print('JOB_CONTEXT_INVALID field=repositoryRoot',file=sys.stderr); raise SystemExit(1)
if trust.get('dagPath') != c['dagPath'] or trust.get('dagDigest') != c['dagDigest']: print('JOB_CONTEXT_INVALID field=identity',file=sys.stderr); raise SystemExit(1)
if trust.get('baseSha') != c['baseSha'] or (base_arg and base_arg != c['baseSha']): print('JOB_CONTEXT_INVALID field=baseSha',file=sys.stderr); raise SystemExit(1)
rec=trust.get('jobs',{}).get(c['jobId'])
if not rec: print('JOB_CONTEXT_INVALID field=jobId',file=sys.stderr); raise SystemExit(1)
trusted_wt=os.path.realpath(rec.get('worktreePath',''))
if not trusted_wt or c['worktreePath'] != trusted_wt or (wt_arg and os.path.realpath(wt_arg)!=trusted_wt): print('JOB_CONTEXT_INVALID field=worktreePath',file=sys.stderr); raise SystemExit(1)
if c['repositoryRoot'] != root or c['status'] != rec.get('status'): print('JOB_CONTEXT_INVALID field=status',file=sys.stderr); raise SystemExit(1)
for k in ('role','profile','modelTier','modelId','provider','lifecycle','effort','dependsOn','writeScope','readScope','verify','lenses','objective'):
 if c[k] != rec.get(k): print('JOB_CONTEXT_INVALID field='+k,file=sys.stderr); raise SystemExit(1)
try: dag=json.load(open(trust['dagPath'],encoding='utf8'))
except Exception: print('JOB_CONTEXT_INVALID field=dagPath',file=sys.stderr); raise SystemExit(1)
if hashlib.sha256(json.dumps(dag,sort_keys=True,separators=(',',':')).encode()).hexdigest()!=trust['dagDigest']: print('JOB_CONTEXT_INVALID field=dagDigest',file=sys.stderr); raise SystemExit(1)
source_rec=next((j for j in dag.get('jobs',[]) if j.get('id')==c['jobId']),None)
if source_rec is None: print('JOB_CONTEXT_INVALID field=dagJob',file=sys.stderr); raise SystemExit(1)
for k in ('role','profile','modelTier','dependsOn','writeScope','readScope','verify','lenses','objective'):
 if c[k] != source_rec.get(k,[] if k in ('readScope',) else None): print('JOB_CONTEXT_INVALID field=dag.'+k,file=sys.stderr); raise SystemExit(1)
if c['objective'].strip()!=c['objective'] or c['objectiveDigest']!=hashlib.sha256(c['objective'].encode()).hexdigest(): print('JOB_CONTEXT_INVALID field=objective',file=sys.stderr); raise SystemExit(1)
profiles=json.load(open(profiles_path,encoding='utf8')); prof=profiles.get('profiles',{}).get(c['profile']); model=prof and prof.get('models',{}).get(c['modelTier']); info=profiles.get('modelRegistry',{}).get(model) if model else None
if (not prof or not info or prof.get('role') != c['role'] or model != c['modelId'] or
    c['provider'] != info.get('provider') or c['lifecycle'] != info.get('lifecycle') or
    c['effort'] != prof.get('effort',{}).get(c['modelTier']) or c['effort'] not in info.get('efforts',[]) or
    c['role'] not in info.get('roles',[]) or info.get('lifecycle') not in ('active','trial') or
    {'profile':c['profile'],'tier':c['modelTier']} not in info.get('routes',[])):
 print('JOB_CONTEXT_INVALID field=route',file=sys.stderr); raise SystemExit(1)
print('JOB_CONTEXT_OK')
PY
}
job_default_adapter() {
 local context=$1
 [ -f "$context" ] || return 1
 [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || { echo 'HAIP configuration missing' >&2; return 1; }
 local model effort role
 model=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["modelId"])' "$context") || return 1
 effort=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["effort"])' "$context") || return 1
 role=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["role"])' "$context") || return 1
 python3 - "$job_profiles_file" "$role" "$model" "$effort" <<'PY' || return 1
import json,sys
p=json.load(open(sys.argv[1],encoding='utf8')); role,model,effort=sys.argv[2:5]
e=p.get('modelRegistry',{}).get(model)
if not e or e.get('lifecycle') not in ('active','trial'): print('UNSUPPORTED_MODEL_ROUTE',file=sys.stderr); raise SystemExit(1)
if role not in e.get('roles',[]): print('UNSUPPORTED_ROLE_ROUTE',file=sys.stderr); raise SystemExit(1)
if effort not in e.get('efforts',[]): print('UNSUPPORTED_EFFORT_ROUTE',file=sys.stderr); raise SystemExit(1)
PY
 command -v claude >/dev/null 2>&1 || { echo 'CLAUDE_ENGINE_MISSING' >&2; return 1; }
 claude --model "$model" --effort "$effort" --agent "$role" -p "$(cat "$context")"
}
job_omp_adapter_load() { . "$job_framework_root/lib/job-omp.sh"; job_omp_adapter "$1"; }
job_adapter_new() {
 local callback=${1:-}
 [ -n "$callback" ] && declare -F "$callback" >/dev/null || { echo 'ADAPTER_INVALID construction' >&2; return 1; }
 JOB_ADAPTER_CALLBACK=$callback
}
job_adapter_dispatch() {
 local context=$1 callback
 [ -f "$context" ] || { echo 'JOB_CONTEXT_INVALID field=file' >&2; return 1; }
 callback="${JOB_ADAPTER_CALLBACK:-job_default_adapter}"
 if [ "${LOOPS_JOB_ADAPTER:-}" = omp ] || { [ -f .loops/engine ] && [ "$(cat .loops/engine 2>/dev/null)" = omp ]; }; then
  callback="${JOB_ADAPTER_CALLBACK:-job_omp_adapter_load}"
 fi
 declare -F "$callback" >/dev/null || { echo 'ADAPTER_INVALID construction' >&2; return 1; }
 local root wt base context_dir
 context_dir=$(cd "$(dirname "$context")" 2>/dev/null && pwd -P) || return 1
 case "$context_dir" in */.loops/runs/*) ;; *) echo 'JOB_CONTEXT_INVALID field=location' >&2; return 1 ;; esac
 root=$(cd "$context_dir/../../.." 2>/dev/null && pwd -P) || return 1
 job_context_validate "$context" "$root" "" "" || return 1
 "$callback" "$context"
 rm -f "$context"
}

job_context_create() {
 local dag=$1 job=$2 runid=$3 dispatchid=$4 root=$5 worktree=$6 out=$7 correlation=${8:-}
 python3 - "$dag" "$job" "$runid" "$dispatchid" "$root" "$worktree" "$out" <<'PY'
import hashlib,json,os,sys,tempfile,subprocess
p,jid,run,did,root,wt,out=sys.argv[1:]
root=os.path.realpath(root); wt=os.path.realpath(wt); p=os.path.realpath(p)
ledger_path=os.path.join(root,'.loops','runs',run,'jobs.json')
try:
 ledger=json.load(open(ledger_path,encoding='utf8')); d=json.load(open(p,encoding='utf8'))
except Exception: print('JOB_CONTEXT_INVALID field=ledger',file=sys.stderr); raise SystemExit(1)
dag_bytes=json.dumps(d,sort_keys=True,separators=(',',':')).encode(); dag_digest=hashlib.sha256(dag_bytes).hexdigest()
rec=next((x for x in d['jobs'] if x['id']==jid),None); entry=ledger.get('jobs',{}).get(jid)
if not rec or not entry: print('JOB_CONTEXT_INVALID field=jobId',file=sys.stderr); raise SystemExit(1)
trust_path=os.path.join(os.path.dirname(ledger_path),'context-trust.json')
try: trust=json.load(open(trust_path,encoding='utf8'))
except Exception: print('JOB_CONTEXT_INVALID field=trust',file=sys.stderr); raise SystemExit(1)
if trust.get('dagPath') != p or trust.get('dagDigest') != dag_digest or trust.get('repositoryRoot') != root: print('JOB_CONTEXT_INVALID field=identity',file=sys.stderr); raise SystemExit(1)
if trust.get('jobs',{}).get(jid,{}).get('worktreePath') and os.path.realpath(trust['jobs'][jid]['worktreePath']) != wt: print('JOB_CONTEXT_INVALID field=worktreePath',file=sys.stderr); raise SystemExit(1)
trusted=trust.get('jobs',{}).get(jid)
if not trusted: print('JOB_CONTEXT_INVALID field=jobTrust',file=sys.stderr); raise SystemExit(1)
for key in ('role','profile','modelTier','dependsOn','writeScope','readScope','verify','lenses','objective'):
 expected=rec.get(key,[] if key=='readScope' else None)
 if trusted.get(key) != expected: print('JOB_CONTEXT_INVALID field=dag.'+key,file=sys.stderr); raise SystemExit(1)
if not isinstance(rec.get('objective'),str) or not rec['objective'] or rec['objective'].strip()!=rec['objective']: print('JOB_CONTEXT_INVALID field=objective',file=sys.stderr); raise SystemExit(1)
ctx={'jobId':jid,'role':trusted['role'],'profile':trusted['profile'],'modelTier':trusted['modelTier'],'modelId':trusted['modelId'],'provider':trusted['provider'],'effort':trusted['effort'],'lifecycle':trusted['lifecycle'],'status':entry['state'],'objective':trusted['objective'],'objectiveDigest':hashlib.sha256(trusted['objective'].encode()).hexdigest(),'dependsOn':trusted['dependsOn'],'writeScope':trusted['writeScope'],'readScope':trusted.get('readScope',[]),'verify':trusted['verify'],'lenses':trusted['lenses'],'runId':run,'dispatchId':did,'baseSha':ledger['baseSha'],'dagPath':p,'dagDigest':dag_digest,'repositoryRoot':root,'worktreePath':wt}
if set(ctx)!=set('jobId role profile modelTier modelId provider effort lifecycle status objective objectiveDigest dependsOn writeScope readScope verify lenses runId dispatchId baseSha dagPath dagDigest repositoryRoot worktreePath'.split()): print('JOB_CONTEXT_INVALID field=keys',file=sys.stderr); raise SystemExit(1)
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
p,j,w=sys.argv[1:]; d=json.load(open(p)); d['jobs'][j]['worktree']=w
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
 local dag=$1 runid=${2:-$(date -u +%Y%m%dT%H%M%SZ)} root run_dir ledger base trust
 [ -f "$dag" ] || { echo DAG_INPUT_MISSING >&2; return 1; }
 root=$(git rev-parse --show-toplevel) || return 1
 job_validate_dag "$dag" >/dev/null || return 1
 run_dir=$(job_executor_init "$root" "$runid" "$dag") || return 1
 ledger=$run_dir/jobs.json; base=$(job_lifecycle_ledger_read "$ledger" "d['baseSha']")
 job_context_trust_init "$dag" "$run_dir" "$root" || return 1
 trust=$run_dir/context-trust.json
 trap 'job_executor_release_lock' RETURN
 while :; do
  local ready=() jid wt ctx item rc=0 pids=()
  while IFS=$'\t' read -r jid state; do [ "$state" = ready ] && ready+=("$jid"); done < <(job_lifecycle_ready "$ledger")
  [ "${#ready[@]}" -gt 0 ] || break
  for jid in "${ready[@]}"; do
   role=$(python3 - "$dag" "$jid" <<'PY'
import json,sys
print(next(x['role'] for x in json.load(open(sys.argv[1]))['jobs'] if x['id']==sys.argv[2]))
PY
) || return 1
   if [ "$role" = reviewer ]; then
    dep=$(python3 - "$dag" "$jid" <<'PY'
import json,sys
j=next(x for x in json.load(open(sys.argv[1]))['jobs'] if x['id']==sys.argv[2]); print(j['dependsOn'][0])
PY
) || return 1
    worker_commit=$(git -C "$(job_lifecycle_ledger_read "$ledger" "d['jobs']['$dep']['worktree']")" rev-parse HEAD) || return 1
    wt=$(job_executor_review_worktree_create "$root" "$runid" "$jid" "$worker_commit" | awk -F '\t' '{print $2}') || return 1
    job_runtime_set_worktree "$ledger" "$jid" "$wt"
   else
    wt=$(job_executor_worktree_create "$root" "$runid" "$jid" "$base" | awk -F '\t' '{print $2}') || return 1
    job_runtime_set_worktree "$ledger" "$jid" "$wt"
   fi
   job_executor_transition "$ledger" "$jid" ready >/dev/null; job_executor_transition "$ledger" "$jid" running >/dev/null
   if [ "$role" = reviewer ]; then job_executor_snapshot_worktree "$wt" "$run_dir/$jid.reviewer-before" || return 1; fi
   job_context_trust_update "$trust" "$jid" "$wt" running || return 1
   ctx="$run_dir/$jid.context.json"; job_context_create "$dag" "$jid" "$runid" "dispatch-$jid" "$root" "$wt" "$ctx"; job_adapter_dispatch "$ctx" & pids+=("$!:$jid")
  done
  for item in "${pids[@]}"; do jid=${item#*:}; if wait "${item%%:*}" && { role=$(python3 - "$dag" "$jid" <<'PY'
import json,sys
print(next(x['role'] for x in json.load(open(sys.argv[1]))['jobs'] if x['id']==sys.argv[2]))
PY
 ); if [ "$role" = reviewer ]; then reviewer_wt=$(job_lifecycle_ledger_read "$ledger" "d['jobs']['$jid']['worktree']"); job_executor_worktree_unchanged "$reviewer_wt" "$run_dir/$jid.reviewer-before"; else job_lifecycle_scope_gate "$ledger" "$jid"; fi; }; then job_executor_transition "$ledger" "$jid" passed >/dev/null; job_context_trust_update "$trust" "$jid" "$(job_lifecycle_ledger_read "$ledger" "d['jobs']['$jid']['worktree']")" passed >/dev/null 2>&1 || true; job_review_plan "$dag" "$jid" > "$run_dir/$jid.review-lenses"; else job_executor_transition "$ledger" "$jid" failed >/dev/null 2>&1 || true; job_lifecycle_block_dependents "$ledger" "$jid" >/dev/null || true; rc=1; fi; done
  [ "$rc" -eq 0 ] || return "$rc"
 done
 printf 'RUN_RECONCILIATION_READY %s\n' "$ledger"
}
