#!/usr/bin/env bash
# LOOPS reflex: guard obviously destructive Bash calls before they run.
# Contract: PreToolUse hook. Reads the tool-call JSON on stdin. Exit 0 = allow.
# Exit 2 = block (stderr is surfaced to the model). This hook only ever blocks
# a short, high-confidence blocklist; everything else passes through untouched.
# It never mutates the command — rtk rewriting stays in its own hook.

set -euo pipefail

input="$(cat 2>/dev/null || true)"

# Extract the command string; degrade gracefully if jq is missing.
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  cmd="$input"
fi

[ -z "$cmd" ] && exit 0

# High-confidence destructive patterns. Deliberately narrow to avoid false blocks.
block() { echo "LOOPS guard: refused — $1. Re-run intentionally if this was deliberate." >&2; exit 2; }

case "$cmd" in
  *"rm -rf /"|*"rm -rf /"*|*"rm -rf ~"*|*"rm -rf \$HOME"*) block "recursive delete of a root/home path" ;;
  *"git push"*"--force"*|*"git push"*" -f "*)               block "force push (rewrites shared history)" ;;
  *"curl"*"| sh"*|*"curl"*"| bash"*|*"wget"*"| sh"*)        block "piping a network download straight into a shell" ;;
  *"mkfs."*|*" dd if="*"of=/dev/"*)                          block "raw disk write" ;;
esac

exit 0
