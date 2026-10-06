#!/usr/bin/env bash

# The session model and its context window are one setting, not two.
#
# Claude Code has no per-model window control: `modelOverrides` maps model ids to
# provider ids and carries no window, and CLAUDE_CODE_MAX_CONTEXT_TOKENS is a
# single global number. So a model switch that forgets the window silently caps
# the new model at the old one's size. `session set` writes both or neither.

# Every model gets a 1000000-token window unless it has an explicit entry here.
# Add an entry only to override that default with a measurement behind it.
session_measured_window() {
  case "$1" in
    claude-sonnet-5-5|claude-opus-5-5|gpt-6-luna|gpt-6.1-sol) printf '1000000\n' ;;
    *) printf '1000000\n' ;;
  esac
}

# Resolve the window for a model id. Prints "<window>\t<source>", where an empty
# window means the key must be *removed* rather than guessed at, and source is one
# of gateway / measured / native / unknown.
session_window() {
  local id="$1" response window
  case "$id" in
    claude-sonnet-5-5|claude-opus-5-5|gpt-6-luna|gpt-6.1-sol)
      printf '%s\tmeasured\n' "$(session_measured_window "$id")"
      return 0
      ;;
    haiku|sonnet|opus|claude-*)
      # Claude Code ships real windows for these; an override could only shrink them.
      printf '\tnative\n'
      return 0
      ;;
  esac
  if response=$(curl -fsS "$ANTHROPIC_BASE_URL/v1/models" \
    -H "x-api-key: $ANTHROPIC_AUTH_TOKEN"); then
    :
  else
    printf 'loops: unable to fetch available models\n' >&2
    return 1
  fi
  if ! printf '%s\n' "$response" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
    printf 'loops: received unparseable model response\n' >&2
    return 1
  fi
  if ! printf '%s\n' "$response" \
    | jq -e --arg id "$id" 'any(.data[]; .id == $id)' >/dev/null 2>&1; then
    printf 'loops: model %s is not served by the gateway\n' "$id" >&2
    return 1
  fi
  window=$(printf '%s\n' "$response" | jq -r --arg id "$id" \
    'first(.data[] | select(.id == $id) | .max_input_tokens) // empty')
  if [ -n "$window" ]; then
    printf '%s\tgateway\n' "$window"
    return 0
  fi
  printf '%s\tdefault\n' "$(session_measured_window "$id")"
}

session_settings_path() {
  case "${1-}" in
    --user) printf '%s/.claude/settings.json\n' "$HOME" ;;
    '') printf '%s\n' "$PWD/.claude/settings.json" ;;
    *) return 2 ;;
  esac
}

cmd_session() {
  local subcommand="${1-}"
  local profiles_file="${LOOPS_PROFILES_FILE:-$SCRIPT_DIR/templates/job-profiles.json}"
  shift || true

  case "$subcommand" in
    show)
      local path
      if ! path=$(session_settings_path "${1-}"); then
        printf 'usage: cmd_session show [--user]\n' >&2
        return 2
      fi
      if [ ! -f "$path" ]; then
        printf 'loops: no settings at %s\n' "$path" >&2
        return 1
      fi
      jq -r --arg path "$path" '
        "settings\t" + $path,
        "model\t" + (.model // "(default)"),
        "window\t" + (.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS // "(claude code default)")
      ' "$path"
      ;;

    set)
      local id="${1-}" scope="${2-}" path resolved window source
      if [ -z "$id" ]; then
        printf 'usage: cmd_session set <model-id> [--user]\n' >&2
        return 2
      fi
      if ! path=$(session_settings_path "$scope"); then
        printf 'usage: cmd_session set <model-id> [--user]\n' >&2
        return 2
      fi
      if ! python3 - "$profiles_file" "$id" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); m=p['modelRegistry'].get(sys.argv[2])
if not m or m['provider']!='haip' or m['lifecycle']!='active' or 'orchestrator' not in m.get('roles',[]):
 print('loops: model is not an active HAIP orchestrator route',file=sys.stderr); raise SystemExit(1)
PY
      then return 1; fi
      if ! resolved=$(session_window "$id"); then
        return 1
      fi
      window=${resolved%%$'\t'*}
      source=${resolved##*$'\t'}

      SESSION_MODEL="$id" SESSION_WINDOW="$window" python3 - "$path" <<'PY'
import json
import os
import sys

path = sys.argv[1]
model = os.environ["SESSION_MODEL"]
window = os.environ["SESSION_WINDOW"]

try:
    with open(path) as handle:
        settings = json.load(handle)
except FileNotFoundError:
    settings = {}
if not isinstance(settings, dict):
    raise SystemExit(f"loops: {path} is not a settings object")

settings["model"] = model
env = settings.get("env")
if not isinstance(env, dict):
    env = {}
if window:
    env["CLAUDE_CODE_MAX_CONTEXT_TOKENS"] = window
else:
    env.pop("CLAUDE_CODE_MAX_CONTEXT_TOKENS", None)
if env:
    settings["env"] = env
else:
    settings.pop("env", None)

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
temporary = path + ".session.tmp"
with open(temporary, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
os.replace(temporary, path)
PY

      case "$source" in
        native)
          printf '%s: %s (claude code knows its window; override removed)\n' "$path" "$id"
          ;;
        unknown)
          printf '%s: %s (window unknown — claude code will assume its default)\n' "$path" "$id"
          printf 'loops: measure it and add it to session_measured_window in lib/session.sh\n' >&2
          ;;
        *)
          printf '%s: %s (window %s, from %s)\n' "$path" "$id" "$window" "$source"
          ;;
      esac
      printf 'loops: takes effect in new sessions\n'
      ;;

    *)
      printf 'usage: cmd_session {show|set} [--user]\n' >&2
      return 2
      ;;
  esac
}
