#!/usr/bin/env bash
# Dispatch ledger primitives. Source this file from a shell with bash 4+.

job_dispatch_root="${JOB_DISPATCH_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
job_dispatch_profiles="${JOB_DISPATCH_PROFILES:-$job_dispatch_root/templates/job-profiles.json}"
job_dispatch_run=""
job_dispatch_state=""
job_dispatch_lock=""

_job_dispatch_die() { printf '%s\n' "$1" >&2; return 1; }
_job_dispatch_python() { python3 - "$@"; }

job_dispatch_init() {
  [ "$#" -ge 1 ] || { echo 'usage: job_dispatch_init <run-id> [root]' >&2; return 2; }
  job_dispatch_run=$1; job_dispatch_root=${2:-$job_dispatch_root}
  job_dispatch_state="$job_dispatch_root/.loops/runs/$job_dispatch_run/dispatch.json"
  job_dispatch_lock="$job_dispatch_state.lock"
  mkdir -p "$(dirname "$job_dispatch_state")"
  [ -e "$job_dispatch_state" ] || printf '%s\n' '{"version":1,"sequence":0,"dispatches":{},"outputs":{},"consumptions":[],"final":null,"counters":{"dispatched":0,"useful":0,"duplicate":0,"rejected":0,"cancelled":0,"unconsumed":0,"acceptedOutputs":0,"consumptionRecords":0,"running":0,"builders":0}}' > "$job_dispatch_state"
}

_job_dispatch_update() {
  local operation=$1; shift
  [ -n "$job_dispatch_state" ] || { echo 'DISPATCH_STATE_UNINITIALIZED' >&2; return 1; }
  ( set -o noclobber; : > "$job_dispatch_lock" ) 2>/dev/null || { echo 'DISPATCH_LOCK_CONTENTION' >&2; return 1; }
  trap 'rm -f "$job_dispatch_lock"' RETURN
  python3 - "$job_dispatch_state" "$operation" "$@" <<'PY'
import hashlib,json,os,sys,tempfile,time
p,op=sys.argv[1:3]; args=sys.argv[3:]
with open(p,encoding='utf8') as f: s=json.load(f)
def norm(x): return sorted(set(x.lower().split()))
def paths(x): return sorted(set(x))
def fail(x): print(x,file=sys.stderr); raise SystemExit(1)
def save():
 s['sequence']+=1
 d=os.path.dirname(p); fd,t=tempfile.mkstemp(prefix='.dispatch.',dir=d,text=True)
 with os.fdopen(fd,'w',encoding='utf8') as f:
  json.dump(s,f,separators=(',',':'),sort_keys=True); f.flush(); os.fsync(f.fileno())
 os.replace(t,p)
def counter(k,n=1): s['counters'][k]=s['counters'].get(k,0)+n
if op=='create':
 # id owner role objective inputs schema output scope deps consumer budget stop generation token profile tier requested_model
 if len(args)!=13: fail('DISPATCH_CREATE_USAGE')
 did,owner,role,obj,inputs,schema,out,scope,deps,consumer,budget,stop,generation=args
 token=os.environ.get('JOB_DISPATCH_TOKEN','') or hashlib.sha256((did+str(generation)).encode()).hexdigest()[:32]
 profile=os.environ.get('JOB_DISPATCH_PROFILE',''); tier=os.environ.get('JOB_DISPATCH_TIER',''); model=os.environ.get('JOB_DISPATCH_MODEL','')
 if not all((did,owner,role,obj,schema,out,consumer,budget,stop,token)): fail('DISPATCH_FIELD_EMPTY')
 if did in s['dispatches']: fail('DISPATCH_DUPLICATE id='+did)
 if schema not in {'exploration-report','contract-proposal','builder-report','evaluator-report'}: fail('DISPATCH_OUTPUT_SCHEMA_UNKNOWN id='+schema)
 try: budget=int(budget); generation=int(generation)
 except: fail('DISPATCH_FIELD_INVALID')
 if budget<1 or generation<1: fail('DISPATCH_FIELD_INVALID')
 objectives=' '.join(norm(obj)); scopes=paths(scope.split(',')) if scope else []
 for old in s['dispatches'].values():
  if old['state'] in ('pending','active'):
   for field,a,b in [('objective',objectives,old['objective']),('output',out,old['output']),('schema',schema,old['schema']),('scope',scopes,old['scope'])]:
    if a==b and not (did in old.get('consumers',[]) or old['id'] in deps): fail(f'DISPATCH_OVERLAP field={field} left={old["id"]} right={did}')
 if role not in ('explorer','planner','builder','evaluator','orchestrator'): fail('DISPATCH_ROLE_INVALID')
 if int(s['counters'].get('running',0))>=4: fail('DISPATCH_GLOBAL_CAP')
 if role=='builder' and int(s['counters'].get('builders',0))>=4: fail('DISPATCH_BUILDER_CAP')
 if any(d not in s['dispatches'] for d in deps.split(',') if d): fail('DISPATCH_DEPENDENCY_UNKNOWN')
 for d in deps.split(',') if deps else []:
  if s['dispatches'][d].get('consumer') not in ('',consumer) and d not in s['dispatches']: fail(f'DISPATCH_DEPENDENCY_DIRECTION producer={d} consumer={did}')
 rec={'id':did,'owner':owner,'role':role,'objective':objectives,'inputs':sorted(set(filter(None,inputs.split(',')))),'schema':schema,'output':out.lower(),'scope':scopes,'dependencies':sorted(set(filter(None,deps.split(',')))),'consumer':consumer,'budget':budget,'remainingBudget':budget,'stop':stop,'generation':generation,'token':token,'state':'active','attempt':1,'accepted':False,'cancelled':False,'profile':profile,'tier':tier,'model':model,'consumers':[]}
 s['dispatches'][did]=rec; counter('dispatched'); counter('running');
 if role=='builder': counter('builders')
 save(); print(token)
elif op=='model':
 if len(args)!=2: fail('ROUTE_USAGE')
 profile,tier=args
 try:
  q=json.load(open(os.environ.get('JOB_DISPATCH_PROFILES',sys.argv[0]),encoding='utf8'))['profiles'][profile]
  if tier not in q['tiers']: fail('ROUTE_INVALID')
  print(q['models'][tier])
 except KeyError: fail('ROUTE_INVALID')
elif op=='escalate':
 if len(args)!=3: fail('ESCALATION_USAGE')
 did,reason,target=args; r=s['dispatches'].get(did)
 if not r: fail('DISPATCH_UNKNOWN id='+did)
 if r['state']!='active' or r['attempt']>=r['budget']: fail('DISPATCH_ESCALATION_BLOCKED id='+did)
 try:
  q=json.load(open(os.environ['JOB_DISPATCH_PROFILES'],encoding='utf8'))['profiles'][r['profile']]
  if q['escalation'].get(r['tier'])!=target: fail('DISPATCH_ESCALATION_NON_ADJACENT')
  model=q['models'][target]
 except KeyError: fail('DISPATCH_ESCALATION_BLOCKED')
 r['attempt']+=1; r['generation']+=1; r['tier']=target; r['model']=model; r['remainingBudget']-=1
 r.setdefault('escalations',[]).append({'jobId':r.get('jobId',did),'attempt':r['attempt'],'reason':reason,'sourceTier':r.get('sourceTier',target),'targetTier':target,'model':model,'runId':job_dispatch_run})
 save(); print(model)
elif op=='result':
 if len(args)!=5: fail('RESULT_USAGE')
 did,state,generation,token,output_sha=args; r=s['dispatches'].get(did)
 if not r: fail(f'DISPATCH_LATE_RESULT dispatch={did} generation={generation} token={token}')
 if r['state']!='active' or str(r['generation'])!=str(generation) or r['token']!=token: fail(f'DISPATCH_LATE_RESULT dispatch={did} generation={generation} token={token}')
 if state not in ('passed','failed','blocked','conflicted','cancelled','rejected'): fail('DISPATCH_STATE_INVALID')
 r['state']=state; r['terminalSequence']=s['sequence']+1; r['outputSha']=output_sha; counter('running',-1); counter('builders',-1 if r['role']=='builder' else 0)
 if state=='cancelled': r['cancelled']=True; counter('cancelled')
 elif state=='rejected': counter('rejected')
 save(); print('DISPATCH_TERMINAL_OK')
elif op=='accept':
 if len(args)!=4: fail('OUTPUT_USAGE')
 did,name,schema,digest=args; r=s['dispatches'].get(did)
 if not r or r['state'] not in ('passed','failed'): fail('DISPATCH_OUTPUT_REJECTED')
 key=did+'\x00'+name.lower()
 if key in s['outputs']: fail(f'DISPATCH_OUTPUT_CONFLICT producer={did} output={name.lower()}')
 s['outputs'][key]={'producer':did,'output':name.lower(),'schema':schema,'digest':digest,'generation':r['generation'],'token':r['token'],'accepted':True}; r['accepted']=True; counter('acceptedOutputs'); save(); print('OUTPUT_ACCEPTED')
elif op=='consume':
 if len(args)!=3: fail('CONSUME_USAGE')
 did,name,consumer=args; key=did+'\x00'+name.lower(); o=s['outputs'].get(key)
 if not o: fail('DISPATCH_OUTPUT_MISSING')
 rec={'producer':did,'output':o['output'],'schema':o['schema'],'consumer':consumer,'sequence':s['sequence']+1,'generation':o['generation'],'token':o['token'],'sha256':o['digest']}
 if rec in s['consumptions']: fail('DISPATCH_CONSUMPTION_DUPLICATE')
 s['consumptions'].append(rec); s['dispatches'][did]['consumers'].append(consumer); counter('consumptionRecords'); counter('useful'); save(); print('CONSUMPTION_RECORDED')
elif op=='final':
 if len(args)!=2: fail('FINAL_USAGE')
 consumer,digests=args; ds=sorted(filter(None,digests.split(','))); known=sorted(x['sha256'] for x in s['consumptions'])
 if any(x not in known for x in ds): fail('DISPATCH_FINAL_CONSUMPTION_MISSING')
 s['final']={'consumer':consumer,'digests':ds}; save(); print('FINAL_CONSUMPTION_RECORDED')
elif op=='cancel':
 if len(args)!=1: fail('CANCEL_USAGE')
 did=args[0]; r=s['dispatches'].get(did)
 if not r or r['state']!='active': fail('DISPATCH_CANCEL_INVALID')
 r['state']='cancelled'; r['cancelled']=True; counter('running',-1); counter('builders',-1 if r['role']=='builder' else 0); counter('cancelled'); save(); print('DISPATCH_CANCELLED')
elif op=='replace':
 if len(args)!=3: fail('REPLACE_USAGE')
 old,new,owner=args; r=s['dispatches'].get(old)
 if not r or r['state']!='cancelled': fail('DISPATCH_REPLACEMENT_INVALID')
 os.environ['JOB_DISPATCH_TOKEN']=hashlib.sha256((new+str(r['generation']+1)).encode()).hexdigest()[:32]
 # Replacement is a new record with only remaining budget.
 r['remainingBudget']=max(0,r['remainingBudget']); print(r['remainingBudget'])
elif op=='reconcile':
 for r in s['dispatches'].values():
  if r['state']=='active': fail('DISPATCH_RECONCILE_BLOCKED')
 accepted=len(s['outputs']); consumed=len(s['consumptions']); s['counters']['unconsumed']=accepted-consumed
 if s['counters']['unconsumed']<0 or s['counters']['dispatched'] != s['counters']['useful']+s['counters']['duplicate']+s['counters']['rejected']+s['counters']['cancelled']+s['counters']['unconsumed']: fail('DISPATCH_RECONCILIATION_MISMATCH')
 save(); print('DISPATCH_RECONCILED dispatched=%s useful=%s unconsumed=%s' % (s['counters']['dispatched'],s['counters']['useful'],s['counters']['unconsumed']))
elif op=='show':
 print(json.dumps(s,separators=(',',':'),sort_keys=True))
else: fail('DISPATCH_OPERATION_UNKNOWN')
PY
}

job_dispatch_model() { JOB_DISPATCH_PROFILES="$job_dispatch_profiles" _job_dispatch_update model "$@"; }
job_dispatch_create() { JOB_DISPATCH_PROFILES="$job_dispatch_profiles" _job_dispatch_update create "$@"; }
job_dispatch_escalate() { JOB_DISPATCH_PROFILES="$job_dispatch_profiles" _job_dispatch_update escalate "$@"; }
job_dispatch_result() { _job_dispatch_update result "$@"; }
job_dispatch_accept_output() { _job_dispatch_update accept "$@"; }
job_dispatch_consume() { _job_dispatch_update consume "$@"; }
job_dispatch_final_answer() { _job_dispatch_update final "$@"; }
job_dispatch_cancel() { _job_dispatch_update cancel "$@"; }
job_dispatch_replace() { _job_dispatch_update replace "$@"; }
job_dispatch_reconcile() { _job_dispatch_update reconcile "$@"; }
job_dispatch_show() { _job_dispatch_update show; }

# Compatibility aliases used by direct shell fixtures.
job_route_model() { job_dispatch_model "$@"; }
job_dispatch_transition() { job_dispatch_result "$@"; }
job_dispatch_register() { job_dispatch_create "$@"; }
job_dispatch_output() { job_dispatch_accept_output "$@"; }
job_dispatch_account() { job_dispatch_reconcile; }
