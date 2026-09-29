#!/usr/bin/env bash
engine_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

cmd_engine() {
  local state_file=".loops/engine"
  local engine="claude"
  local subcommand="${1:-}"
  local value role prompt model effort binary omp_args route_effort route_profile agents_dir

  if [ -f "$state_file" ]; then
    value="$(cat "$state_file" 2>/dev/null)"
    case "$value" in
      claude|opencode|omp) engine="$value" ;;
      *) engine="claude" ;;
    esac
  fi

  case "$subcommand" in
    show)
      [ "$#" -eq 1 ] || { printf '%s\n' "usage: cmd_engine show" >&2; return 1; }
      binary="$(command -v "$engine" 2>/dev/null)" || {
        printf 'engine binary not found: %s\n' "$engine" >&2
        return 1
      }
      printf '%s %s\n' "$engine" "$binary"
      ;;
    set)
      [ "$#" -eq 2 ] || { printf '%s\n' "usage: cmd_engine set <claude|opencode|omp>" >&2; return 1; }
      value="$2"
      case "$value" in
        claude|opencode|omp) ;;
        *) printf 'unknown engine: %s\n' "$value" >&2; return 1 ;;
      esac
      command -v "$value" >/dev/null 2>&1 || {
        printf 'engine binary not found: %s\n' "$value" >&2
        return 1
      }
      mkdir -p .loops || return 1
      printf '%s\n' "$value" > "$state_file" || return 1
      ;;
    run)
      local dry_run=0
      if [ "${2:-}" = "--dry-run" ]; then
        dry_run=1
        shift
      fi
      [ "$#" -eq 3 ] || { printf '%s\n' "usage: cmd_engine run [--dry-run] <role> <prompt>" >&2; return 1; }
      role="$2"
      prompt="$3"
      case "$role" in
        ''|*/*|.*) printf 'unknown role: %s\n' "$role" >&2; return 1 ;;
      esac
      agents_dir="${LOOPS_AGENTS_DIR:-.claude/agents}"
      model="$(awk '
        NR == 1 { line=$0; sub(/\r$/, "", line); if (line == "---") in_front=1; next }
        { line=$0; sub(/\r$/, "", line) }
        in_front && line == "---" { exit }
        in_front && line ~ /^[[:space:]]*model:[[:space:]]*/ {
          sub(/^[[:space:]]*model:[[:space:]]*/, "", line)
          print line
          exit
        }
      ' "$agents_dir/$role.md" 2>/dev/null)"
      effort="$(awk '
        NR == 1 { line=$0; sub(/\r$/, "", line); if (line == "---") in_front=1; next }
        { line=$0; sub(/\r$/, "", line) }
        in_front && line == "---" { exit }
        in_front && line ~ /^[[:space:]]*effort:[[:space:]]*/ {
          sub(/^[[:space:]]*effort:[[:space:]]*/, "", line)
          print line
          exit
        }
      ' "$agents_dir/$role.md" 2>/dev/null)"
      [ -n "$model" ] && [ -n "$effort" ] || { printf 'unknown role: %s\n' "$role" >&2; return 1; }
      local profiles_file="${LOOPS_PROFILES_FILE:-$engine_root/templates/job-profiles.json}"
      local route_json
      route_json=$(python3 - "$profiles_file" "$role" "$model" "$effort" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); role,model,effort=sys.argv[2:]
projection=p.get('projections',{}).get(role)
m=p.get('modelRegistry',{}).get(model)
if not isinstance(projection,dict) or not isinstance(m,dict): raise SystemExit(1)
if m.get('provider')!='haip' or m.get('lifecycle') not in ('active','trial') or role not in m.get('roles',[]): raise SystemExit(1)
profile_name=projection.get('profile'); tier=projection.get('tier')
profile=p.get('profiles',{}).get(profile_name)
if not isinstance(profile,dict) or profile.get('role') != role: raise SystemExit(1)
if profile.get('models',{}).get(tier) != model: raise SystemExit(1)
if {'profile':profile_name,'tier':tier} not in m.get('routes',[]): raise SystemExit(1)
expected=profile.get('effort',{}).get(tier)
if effort != expected or effort not in m.get('efforts',[]): raise SystemExit(1)
print(expected)
PY
      ) || { echo 'ROUTE_INVALID' >&2; return 1; }
      route_effort="$route_json"
      case "$engine" in
        omp)
          . "${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/job-omp.sh"
          if [ "$dry_run" -eq 1 ]; then
            printf '%s\n' omp --no-session -p "$prompt" --model "haip/$model" --effort "$route_effort"
          else
            route_profile=$(python3 - "$profiles_file" "$role" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); print(p['projections'][sys.argv[2]]['profile'])
PY
) || return 1
          OMP_EFFORT="$route_effort" OMP_PROFILE="$route_profile" omp_engine_run "$role" "$prompt" "$model"
          fi
          ;;
        claude)
          command -v claude >/dev/null 2>&1 || { printf 'engine binary not found: claude\n' >&2; return 1; }
          [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ] || { printf 'HAIP configuration missing\n' >&2; return 1; }
          if [ "$dry_run" -eq 1 ]; then
            printf '%s\n' claude --model "$model" --effort "$route_effort" -p "$prompt"
          else
            exec claude --model "$model" --effort "$route_effort" -p "$prompt"
          fi
          ;;
        opencode)
          printf 'engine opencode is not an approved HAIP route; use claude or omp\n' >&2
          return 1
          ;;
      esac
      ;;
    *)
      printf '%s\n' "usage: cmd_engine {show|set|run [--dry-run] <role> <prompt>}" >&2
      return 1
      ;;
  esac
}
