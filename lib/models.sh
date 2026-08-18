#!/usr/bin/env bash

# Print selectable model ids, marking the current id when supplied.
models_menu_options() {
  local current="${1-}" available id mark
  if ! available=$(cmd_models available); then
    return 1
  fi
  for id in haiku sonnet opus; do
    if [ "$id" = "$current" ]; then mark='>'; else mark=' '; fi
    printf '%s\t%s\n' "$mark" "$id"
  done
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$id" in haiku|sonnet|opus) continue ;; esac
    if [ "$id" = "$current" ]; then mark='>'; else mark=' '; fi
    printf '%s\t%s\n' "$mark" "$id"
  done <<EOF
$available
EOF
}

cmd_models() {
  local subcommand="${1-}"
  shift || true

  case "$subcommand" in
    list)
      if [ "$#" -ne 0 ]; then
        printf 'usage: cmd_models list\n' >&2
        return 2
      fi
      local agents_dir="${LOOPS_AGENTS_DIR:-$SCRIPT_DIR/.claude/agents}" agent path role model
      local agent_paths=("$agents_dir"/*.md)
      if [ ! -f "${agent_paths[0]}" ]; then
        printf 'cmd_models: no agent roster found in %s\n' "$agents_dir" >&2
        return 1
      fi
      for path in "${agent_paths[@]}"; do
        [ -f "$path" ] || continue
        role=${path##*/}
        role=${role%.md}
        model=$(awk '
          NR == 1 && $0 == "---" { in_frontmatter = 1; next }
          in_frontmatter && $0 == "---" { exit }
          in_frontmatter && $0 ~ /^[[:space:]]*model:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*model:[[:space:]]*/, "", line)
            print line
            found = 1
            exit
          }
        ' "$path")
        if [ -z "$model" ]; then
          model='(default)'
        fi
        printf '%s\t%s\n' "$role" "$model"
      done
      ;;

    available)
      if [ "$#" -ne 0 ]; then
        printf 'usage: cmd_models available\n' >&2
        return 2
      fi
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
        case "$set_model" in
          haiku|sonnet|opus) found=1 ;;
          *) found=$(printf '%s\n' "$response" | jq -r --arg wanted "$set_model" '.data[].id | select(. == $wanted)') ;;
        esac
        if [ -z "$found" ]; then
          printf 'cmd_models: model %s is not available (use --force to override)\n' "$set_model" >&2
          return 1
        fi
      fi

      MODEL_ID="$set_model" python3 - "$target" <<'PY'
import os
import re
import sys

path = sys.argv[1]
model = os.environ["MODEL_ID"].encode()
with open(path, "rb") as handle:
    original = handle.read()
lines = original.splitlines(keepends=True)
if not lines or lines[0].rstrip(b"\r\n") != b"---":
    raise SystemExit("cmd_models: missing frontmatter")
closing = None
for index in range(1, len(lines)):
    if lines[index].rstrip(b"\r\n") == b"---":
        closing = index
        break
if closing is None:
    raise SystemExit("cmd_models: unterminated frontmatter")
model_line = re.compile(rb"^([ \t]*model:[ \t]*)[^\r\n]*(\r?\n)?$")
updated = list(lines)
found = False
for index in range(1, closing):
    match = model_line.match(updated[index])
    if match:
        updated[index] = match.group(1) + model + (match.group(2) or b"")
        found = True
        break
if not found:
    newline = b"\r\n" if closing > 0 and lines[closing - 1].endswith(b"\r\n") else b"\n"
    if closing > 0 and not updated[closing - 1].endswith((b"\n", b"\r")):
        updated[closing - 1] += newline
    updated.insert(closing, b"model: " + model + newline)
result = b"".join(updated)
if result != original:
    mode = os.stat(path).st_mode
    temporary = path + ".models.tmp"
    with open(temporary, "wb") as handle:
        handle.write(result)
        os.chmod(temporary, mode)
    os.replace(temporary, path)
PY
      ;;

    *)
      printf 'usage: cmd_models {list|available|menu|set}\n' >&2
      return 2
      ;;
  esac
}
