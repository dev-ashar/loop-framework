#!/usr/bin/env bash

models_registry_file() {
  printf '%s\n' "${LOOPS_PROFILES_FILE:-$SCRIPT_DIR/templates/job-profiles.json}"
}

# Print selectable model ids, marking the current id when supplied.
models_menu_options() {
  local current="${1-}" available id mark
  if ! available=$(cmd_models available); then
    return 1
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if [ "$id" = "$current" ]; then mark='>'; else mark=' '; fi
    printf '%s\t%s\n' "$mark" "$id"
  done <<EOF
$available
EOF
}

cmd_models() {
  local subcommand="${1-}"
  shift || true
  local profiles_file
  profiles_file=$(models_registry_file)

  case "$subcommand" in
    list)
      [ "$#" -eq 0 ] || { printf 'usage: cmd_models list\n' >&2; return 2; }
      python3 - "$profiles_file" "${LOOPS_AGENTS_DIR:-$SCRIPT_DIR/.claude/agents}" <<'PY'
import json,os,sys
p=json.load(open(sys.argv[1],encoding='utf8'))
agents=sys.argv[2]
for role,projection in p['projections'].items():
 path=os.path.join(agents,role+'.md')
 if not os.path.isfile(path):
  continue
 profile=p['profiles'][projection['profile']]
 print('%s\t%s' % (role,profile['models'][projection['tier']]))
PY
      ;;

    available)
      [ "$#" -eq 0 ] || { printf 'usage: cmd_models available\n' >&2; return 2; }
      local response curl_status
      if response=$(curl -fsS --connect-timeout 3 --max-time 10 "$ANTHROPIC_BASE_URL/v1/models" \
        -H "x-api-key: $ANTHROPIC_AUTH_TOKEN"); then
        curl_status=0
      else
        curl_status=$?
      fi
      if [ "$curl_status" -ne 0 ]; then
        printf 'cmd_models: unable to fetch available models\n' >&2
        return 1
      fi
      if ! printf '%s\n' "$response" | jq -e '(.data | type == "array") and all(.data[]; (.id | type == "string"))' >/dev/null 2>&1; then
        printf 'cmd_models: received unparseable model response\n' >&2
        return 1
      fi
      printf '%s\n' "$response" | jq -r '.data[].id' | sort
      ;;

    menu)
      [ "$#" -le 1 ] || { printf 'usage: cmd_models menu [current-model]\n' >&2; return 2; }
      models_menu_options "${1-}"
      ;;

    set)
      local usage='usage: cmd_models set <role> [model-id] [--force] [--effort <level>]'
      local set_role='' set_model='' force='' set_effort='' target
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --force) force=--force ;;
          --effort)
            [ "$#" -ge 2 ] || { printf '%s\n' "$usage" >&2; return 2; }
            set_effort="$2"; shift
            ;;
          --*) printf 'cmd_models: unknown option %s\n' "$1" >&2; return 2 ;;
          *)
            if [ -z "$set_role" ]; then set_role="$1"
            elif [ -z "$set_model" ]; then set_model="$1"
            else printf '%s\n' "$usage" >&2; return 2
            fi
            ;;
        esac
        shift
      done
      [ -n "$set_role" ] || { printf '%s\n' "$usage" >&2; return 2; }
      case "$set_role" in
        .|..|*/*)
          printf 'cmd_models: unknown role %s\n' "$set_role" >&2
          return 1
          ;;
      esac
      case "$set_model$set_effort" in
        *$'\n'*|*$'\r'*)
          printf 'cmd_models: invalid model id\n' >&2
          return 2
          ;;
      esac
      case "$set_effort" in
        ''|low|medium|high|xhigh|max) ;;
        *) printf 'cmd_models: unknown effort %s\n' "$set_effort" >&2; return 2 ;;
      esac
      local agents_dir="${LOOPS_AGENTS_DIR:-$SCRIPT_DIR/.claude/agents}"
      target="$agents_dir/$set_role.md"
      if [ ! -f "$target" ]; then
        printf 'cmd_models: unknown role %s\n' "$set_role" >&2
        return 1
      fi

      local ids
      if [ -z "$set_model" ]; then
        # Interactive: numbered menu of live ids, current one marked.
        local current n=0 id choice mark
        current=$(ROLE_ID="$set_role" python3 - "$profiles_file" <<'PY'
import json,os,sys
p=json.load(open(sys.argv[1])); pr=p['projections'].get(os.environ['ROLE_ID'])
if pr: print(p['profiles'][pr['profile']]['models'][pr['tier']])
PY
) || return 1
        ids=$(cmd_models available | grep -v '^$') || return 1
        [ -n "$ids" ] || { printf 'cmd_models: no models available\n' >&2; return 1; }
        printf 'Models for %s:\n' "$set_role"
        while IFS= read -r id; do
          n=$((n + 1))
          if [ "$id" = "$current" ]; then mark='*'; else mark=' '; fi
          printf '%s %2d) %s\n' "$mark" "$n" "$id"
        done <<IDS
$ids
IDS
        printf 'Choose 1-%d: ' "$n"
        IFS= read -r choice || { printf '\ncmd_models: no selection\n' >&2; return 1; }
        case "$choice" in
          ''|*[!0-9]*) printf 'cmd_models: invalid selection\n' >&2; return 1 ;;
        esac
        if [ "$choice" -lt 1 ] || [ "$choice" -gt "$n" ]; then
          printf 'cmd_models: invalid selection\n' >&2
          return 1
        fi
        set_model=$(printf '%s\n' "$ids" | sed -n "${choice}p")
      elif [ "$force" != '--force' ]; then
        ids=$(cmd_models available) || return 1
        if ! printf '%s\n' "$ids" | grep -Fxq -- "$set_model"; then
          printf 'cmd_models: model %s is not available (use --force to override)\n' "$set_model" >&2
          return 1
        fi
      fi

      MODEL_ID="$set_model" ROLE_ID="$set_role" EFFORT="$set_effort" AGENTS_DIR="$agents_dir" PROFILES_FILE="$profiles_file" python3 - <<'PY'
import json,os,re,tempfile
profiles_path=os.environ['PROFILES_FILE']
agents_dir=os.environ['AGENTS_DIR']
role=os.environ['ROLE_ID']
model=os.environ['MODEL_ID']
effort_arg=os.environ['EFFORT']
with open(profiles_path,encoding='utf8') as f: profiles=json.load(f)
reg=profiles['modelRegistry']
if role not in profiles['projections']:
 raise SystemExit('cmd_models: role is not in the central projection registry')
mine={n:p for n,p in profiles['profiles'].items() if p['role']==role}
entry=reg.get(model)
if entry is None:
 entry=reg[model]={'provider':'haip','lifecycle':'active','roles':[],'efforts':[],'routes':[]}
if entry['provider']!='haip' or entry['lifecycle'] not in ('active','trial'):
 raise SystemExit('cmd_models: model lifecycle is not routable')
if role not in entry['roles']: entry['roles'].append(role)
touched=set()
for pname,prof in mine.items():
 for tier in prof['tiers']:
  old=prof['models'][tier]
  if effort_arg: prof['effort'][tier]=effort_arg
  eff=prof['effort'][tier]
  if eff not in entry['efforts']: entry['efforts'].append(eff)
  prof['models'][tier]=model
  route={'profile':pname,'tier':tier}
  if route not in entry['routes']: entry['routes'].append(route)
  if old!=model:
   touched.add(old)
   oe=reg.get(old)
   if oe: oe['routes']=[r for r in oe.get('routes',[]) if r!=route]
# Prune: drop the role from a model that no longer routes it; drop unused models.
for old in touched:
 oe=reg.get(old)
 if not oe: continue
 if not any(r['profile'] in mine for r in oe['routes']) and role in oe['roles']:
  oe['roles'].remove(role)
 if not oe['roles'] and not oe['routes']: del reg[old]

# Update the projected frontmatter: model, and effort.
proj=profiles['projections'][role]
pr=profiles['profiles'][proj['profile']]
want_model=pr['models'][proj['tier']]; want_effort=pr['effort'][proj['tier']]
target=os.path.join(agents_dir,role+'.md')
with open(target,'rb') as f: original_agent=f.read()
lines=original_agent.splitlines(keepends=True)
if not lines or lines[0].rstrip(b'\r\n') != b'---':
 raise SystemExit('cmd_models: missing frontmatter')
closing=next((i for i in range(1,len(lines)) if lines[i].rstrip(b'\r\n')==b'---'),None)
if closing is None:
 raise SystemExit('cmd_models: unterminated frontmatter')
def rewrite(key,value):
 rx=re.compile(rb'^([ \t]*'+key+rb':[ \t]*)[^\r\n]*(\r?\n)?$')
 for i in range(1,closing):
  m=rx.match(lines[i])
  if m:
   lines[i]=m.group(1)+value.encode()+(m.group(2) or b'\n'); return True
 return False
if not rewrite(b'model',want_model):
 raise SystemExit('cmd_models: projection frontmatter has no model field')
if not rewrite(b'effort',want_effort):
 raise SystemExit('cmd_models: projection frontmatter has no effort field')
agent_bytes=b''.join(lines)

def dump(x):
 j=lambda v: json.dumps(v,separators=(',',':'))
 out=['{']
 keys=list(x)
 for i,k in enumerate(keys):
  v=x[k]; comma=',' if i<len(keys)-1 else ''
  if isinstance(v,dict) and v and all(isinstance(e,dict) for e in v.values()):
   out.append('  %s: {' % j(k))
   sub=list(v)
   for n,s in enumerate(sub):
    out.append('    %s: %s%s' % (j(s),j(v[s]),',' if n<len(sub)-1 else ''))
   out.append('  }'+comma)
  else:
   out.append('  %s: %s%s' % (j(k),j(v),comma))
 out.append('}')
 return '\n'.join(out)+'\n'
def stage(path,data,mode=None):
 fd,tmp=tempfile.mkstemp(prefix='.models.',dir=os.path.dirname(path))
 with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
 if mode is not None: os.chmod(tmp,mode)
 return tmp
reg_bytes=dump(profiles).encode()
mode=os.stat(target).st_mode
staged=[(profiles_path,stage(profiles_path,reg_bytes)),(target,stage(target,agent_bytes,mode))]
try:
 for path,tmp in staged: os.replace(tmp,path)
except Exception:
 for _,tmp in staged:
  if os.path.exists(tmp): os.unlink(tmp)
 raise
print('%s -> %s (%s)' % (role,want_model,want_effort))
PY
      ;;

    *)
      printf 'usage: cmd_models {list|available|menu|set}\n' >&2
      return 2
      ;;
  esac
}
