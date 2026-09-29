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
      if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
        printf 'usage: cmd_models set <role> <model-id> [--force]\n' >&2
        return 2
      fi
      local set_role="$1" set_model="$2" force="${3-}" target
      if [ "$#" -eq 3 ] && [ "$force" != '--force' ]; then
        printf 'cmd_models: unknown option %s\n' "$force" >&2
        return 2
      fi
      case "$set_role" in
        ''|.|..|*/*)
          printf 'cmd_models: unknown role %s\n' "$set_role" >&2
          return 1
          ;;
      esac
      case "$set_model" in
        *$'\n'*|*$'\r'*)
          printf 'cmd_models: invalid model id\n' >&2
          return 2
          ;;
      esac
      local agents_dir="${LOOPS_AGENTS_DIR:-$SCRIPT_DIR/.claude/agents}"
      target="$agents_dir/$set_role.md"
      if [ ! -f "$target" ]; then
        printf 'cmd_models: unknown role %s\n' "$set_role" >&2
        return 1
      fi

      # Validate availability only when requested. Registry/lifecycle validation
      # always runs locally before any projection or frontmatter mutation.
      if [ "$force" != '--force' ]; then
        local response curl_status found
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
        found=$(printf '%s\n' "$response" | jq -r --arg wanted "$set_model" '.data[].id | select(. == $wanted)')
        if [ -z "$found" ]; then
          printf 'cmd_models: model %s is not available (use --force to override)\n' "$set_model" >&2
          return 1
        fi
      fi

      MODEL_ID="$set_model" ROLE_ID="$set_role" PROFILES_FILE="$profiles_file" TARGET="$target" python3 - <<'PY'
import json,os,re,tempfile
profiles_path=os.environ['PROFILES_FILE']
target=os.environ['TARGET']
role=os.environ['ROLE_ID']
model=os.environ['MODEL_ID']
with open(profiles_path,encoding='utf8') as f: profiles=json.load(f)
projection=profiles['projections'].get(role)
if not projection:
 raise SystemExit('cmd_models: role is not in the central projection registry')
profile_name=projection['profile']; tier=projection['tier']
profile=profiles['profiles'].get(profile_name)
entry=profiles['modelRegistry'].get(model)
if not profile or not entry:
 raise SystemExit('cmd_models: model is absent from the central registry')
if entry['provider']!='haip' or entry['lifecycle'] not in ('active','trial') or role not in entry['roles']:
 raise SystemExit('cmd_models: model lifecycle or role is not routable')
if profile['effort'][tier] not in entry['efforts']:
 raise SystemExit('cmd_models: model does not support the projected effort')
old=profile['models'][tier]
if old == model:
 raise SystemExit(0)
old_entry=profiles['modelRegistry'].get(old)
if old_entry:
 old_entry['routes']=[r for r in old_entry.get('routes',[]) if not (r.get('profile')==profile_name and r.get('tier')==tier)]
route={'profile':profile_name,'tier':tier}
if route not in entry.setdefault('routes',[]):
 entry['routes'].append(route)
profile['models'][tier]=model

with open(target,'rb') as f: original_agent=f.read()
lines=original_agent.splitlines(keepends=True)
if not lines or lines[0].rstrip(b'\r\n') != b'---':
 raise SystemExit('cmd_models: missing frontmatter')
closing=next((i for i in range(1,len(lines)) if lines[i].rstrip(b'\r\n')==b'---'),None)
if closing is None:
 raise SystemExit('cmd_models: unterminated frontmatter')
model_line=re.compile(rb'^([ \t]*model:[ \t]*)[^\r\n]*(\r?\n)?$')
updated=list(lines); replaced=False
for i in range(1,closing):
 m=model_line.match(updated[i])
 if m:
  updated[i]=m.group(1)+model.encode()+ (m.group(2) or b'\n'); replaced=True; break
if not replaced:
 raise SystemExit('cmd_models: projection frontmatter has no model field')
agent_bytes=b''.join(updated)

# Stage every projection, registry, and frontmatter update before replacing any.
def stage(path,data,mode=None):
 fd,tmp=tempfile.mkstemp(prefix='.models.',dir=os.path.dirname(path))
 with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
 if mode is not None: os.chmod(tmp,mode)
 return tmp
reg_bytes=(json.dumps(profiles,indent=2,sort_keys=False)+'\n').encode()
mode=os.stat(target).st_mode
staged=[(profiles_path,stage(profiles_path,reg_bytes)),(target,stage(target,agent_bytes,mode))]
try:
 for path,tmp in staged: os.replace(tmp,path)
except Exception:
 for _,tmp in staged:
  if os.path.exists(tmp): os.unlink(tmp)
 raise
PY
      ;;

    *)
      printf 'usage: cmd_models {list|available|menu|set}\n' >&2
      return 2
      ;;
  esac
}
