#!/usr/bin/env bash

cmd_engine() {
  local state_file=".loops/engine"
  local engine="claude"
  local subcommand="${1:-}"
  local value role prompt model binary

  if [ -f "$state_file" ]; then
    value="$(cat "$state_file" 2>/dev/null)"
    case "$value" in
      claude|opencode) engine="$value" ;;
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
      [ "$#" -eq 2 ] || { printf '%s\n' "usage: cmd_engine set <claude|opencode>" >&2; return 1; }
      value="$2"
      case "$value" in
        claude|opencode) ;;
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
      model="$(awk '
        NR == 1 { line=$0; sub(/\r$/, "", line); if (line == "---") in_front=1; next }
        { line=$0; sub(/\r$/, "", line) }
        in_front && line == "---" { exit }
        in_front && line ~ /^[[:space:]]*model:[[:space:]]*/ {
          sub(/^[[:space:]]*model:[[:space:]]*/, "", line)
          print line
          exit
        }
      ' ".claude/agents/$role.md" 2>/dev/null)"
      [ -n "$model" ] || { printf 'unknown role: %s\n' "$role" >&2; return 1; }
      case "$engine" in
        claude)
          command -v claude >/dev/null 2>&1 || { printf 'engine binary not found: claude\n' >&2; return 1; }
          if [ "$dry_run" -eq 1 ]; then
            printf '%s\n' claude --model "$model" -p "$prompt"
          else
            exec claude --model "$model" -p "$prompt"
          fi
          ;;
        opencode)
          command -v opencode >/dev/null 2>&1 || { printf 'engine binary not found: opencode\n' >&2; return 1; }
          if [ "$dry_run" -eq 1 ]; then
            printf '%s\n' opencode run -m "$model" "$prompt"
          else
            exec opencode run -m "$model" "$prompt"
          fi
          ;;
      esac
      ;;
    *)
      printf '%s\n' "usage: cmd_engine {show|set|run [--dry-run] <role> <prompt>}" >&2
      return 1
      ;;
  esac
}
