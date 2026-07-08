#!/usr/bin/env bash
# LOOPS reflex: append a one-line trace to .loops/log.md after each edit.
# Contract: PostToolUse hook. Reads the tool-call JSON on stdin. Always exits 0 —
# logging must never interrupt the loop. Only logs when a .loops/ dir already
# exists in the working directory (i.e. an active loop run); otherwise silent.

set -uo pipefail

logdir=".loops"
[ -d "$logdir" ] || exit 0

input="$(cat 2>/dev/null || true)"

if command -v jq >/dev/null 2>&1; then
  tool="$(printf '%s' "$input" | jq -r '.tool_name // "tool"' 2>/dev/null || echo tool)"
  path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
else
  tool="tool"; path=""
fi

# Only trace state-changing tools; ignore reads/searches.
case "$tool" in
  Edit|Write|NotebookEdit|MultiEdit) ;;
  *) exit 0 ;;
esac

ts="$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'unknown')"
printf '## [%s] %s | %s\n' "$ts" "$tool" "${path:-edit}" >> "$logdir/log.md" 2>/dev/null || true

exit 0
