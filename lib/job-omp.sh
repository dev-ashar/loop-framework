#!/usr/bin/env bash
# Oh My Pi (can1357/oh-my-pi) backend.
# The adapter keeps provider configuration isolated and requires a terminal stream event.

omp_stream_terminal_ok() {
  local stream=$1 line last=''
  [ -f "$stream" ] || return 1
  while IFS= read -r line; do
    [ -n "${line//[[:space:]]/}" ] && last=$line
  done < "$stream"
  [ "$last" = '{"type":"turn_end","status":"completed"}' ]
}

omp_tools_for_profile() {
  python3 - "$1" "${2:-worker-default}" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); profile=p['profiles'].get(sys.argv[2])
if not profile or profile['models'].get(profile['tiers'][0]) not in p['modelRegistry']: raise SystemExit('ROUTE_INVALID')
caps=profile['capabilities']
if profile['role'] in ('architect','planner','reviewer','explorer','merge'):
 seen=['read','grep','glob','todo']
 if any(x in caps for x in ('run-tests','git-read','git-worktree')): seen.append('bash')
 print(','.join(seen)); raise SystemExit(0)
seen=['read','grep','glob','todo']
if any(x in caps for x in ('run-tests','git-read','git-worktree')): seen.append('bash')
if 'write-source' in caps: seen += ['edit','write']
print(','.join(seen))
PY
}

omp_engine_run() {
  local role=$1 prompt=$2 declared_model=${3:-}; shift 2
  [ -n "$declared_model" ] && shift || true
  local config_dir=${OMP_CONFIG_DIR:-${TMPDIR:-/tmp}/loops-omp-config}
  local stream=${OMP_STREAM_FILE:-} model_id=${OMP_MODEL_ID:-$declared_model} profile=${OMP_PROFILE:-worker-default}
  [ -n "$role" ] && [ -n "$prompt" ] || { echo 'OMP_INPUT_INVALID' >&2; return 1; }
  command -v omp >/dev/null 2>&1 || { echo 'engine binary not found: omp' >&2; return 1; }
  [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || { echo 'HAIP configuration missing' >&2; return 1; }
  mkdir -p "$config_dir" || return 1
  local config="$config_dir/models.yml"
  if [ ! -f "$config" ]; then
    sed "s|__HAIP_BASE_URL__|${ANTHROPIC_BASE_URL:-}|g; s|__HAIP_TOKEN_ENV__|${OMP_HAIP_TOKEN_ENV:-ANTHROPIC_AUTH_TOKEN}|g" \
      "${OMP_MODELS_TEMPLATE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/omp/models.yml.template}" > "$config" || return 1
  fi
  local profiles_file="${OMP_PROFILES_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/job-profiles.json}"
  local tools
  [ "$role" = worker ] && [ "$profile" = worker-default ] && [ "$model_id" = gpt-5.6-luna-mantle ] || { echo 'ROUTE_INVALID' >&2; return 1; }
  tools=$(omp_tools_for_profile "$profiles_file" "$profile") || return 1
  [ "$role" = "$(python3 - "$profiles_file" "$profile" <<'PY'
import json,sys; print(json.load(open(sys.argv[1]))['profiles'][sys.argv[2]]['role'])
PY
)" ] || { echo 'ROUTE_INVALID' >&2; return 1; }
  local resolved_effort
  resolved_effort=$(python3 - "$profiles_file" "$profile" "$model_id" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); q=p['profiles'].get(sys.argv[2]); m=p['modelRegistry'].get(sys.argv[3])
if not q or not m or m['provider']!='haip' or m['lifecycle'] not in ('active','trial'): raise SystemExit(1)
if sys.argv[3] != q['models'].get(q['tiers'][0]): raise SystemExit(1)
print(q['effort'][q['tiers'][0]])
PY
  ) || { echo 'ROUTE_INVALID' >&2; return 1; }
  local tmp=${stream:-$(mktemp)} rc=0
  [ -n "$model_id" ] || model_id=gpt-5.6-luna-mantle
  PI_CODING_AGENT_DIR="$config_dir" omp --no-session -p "$prompt" --model "haip/$model_id" --tools "$tools" --effort "$resolved_effort" >"$tmp" 2>&1 || rc=$?
  cat "$tmp"
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return "$rc"; }
  omp_stream_terminal_ok "$tmp" || { rm -f "$tmp"; echo 'OMP_STREAM_TERMINAL_MISSING' >&2; return 1; }
  rm -f "$tmp"
}

job_omp_adapter() {
  local context=$1
  [ -f "$context" ] || { echo 'JOB_CONTEXT_INVALID field=file' >&2; return 1; }
  local root wt job role verify prompt stream model profile objective scope effort
  root=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["repositoryRoot"])' "$context") || return 1
  wt=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["worktreePath"])' "$context") || return 1
  job=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["jobId"])' "$context") || return 1
  role=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["role"])' "$context") || return 1
  verify=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["verify"])' "$context") || return 1
  model=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["modelId"])' "$context") || return 1
  profile=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["profile"])' "$context") || return 1
  objective=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["objective"])' "$context") || return 1
  effort=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["effort"])' "$context") || return 1
  prompt="$(python3 - "$context" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
print('You are the '+c['role']+' job '+c['jobId']+'. Work only within: '+', '.join(c['writeScope']))
print('Objective: '+c['objective'])
print('Verify with: '+c['verify'])
print('Required effort: '+c['effort'])
print('Complete the requested job.')
PY
)"
  stream="${OMP_STREAM_FILE:-$wt/.loops-omp-$job.stream}"
  (cd "$wt" && OMP_STREAM_FILE="$stream" OMP_MODEL_ID="$model" OMP_PROFILE="$profile" OMP_EFFORT="$effort" OMP_PROFILES_FILE="$root/templates/job-profiles.json" omp_engine_run "$role" "$prompt" "$model") || return 1
  rm -f "$stream"
  (cd "$wt" && bash -c "$verify") || { echo "OMP_VERIFY_FAILED job=$job" >&2; return 1; }
  printf 'OMP_JOB_OK job=%s\n' "$job"
}
