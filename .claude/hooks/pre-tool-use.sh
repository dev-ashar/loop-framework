#!/usr/bin/env bash
# LOOPS reflex: guard clear destructive Git and GitHub calls before execution.
# This hook cannot identify agent roles or guarantee every shell mutation is impossible.
# It restricts subagents and leaves authorized main-session Git actions to host permissions.

set -euo pipefail
input="$(cat 2>/dev/null || true)"
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)"
else
  cmd="$input"
  agent_id=""
fi
[ -z "$cmd" ] && exit 0
[ -z "$agent_id" ] && exit 0
block() { echo "LOOPS guard: refused — $1." >&2; exit 2; }

case "$cmd" in
  *"git commit"*|*"git push"*|*"git fetch"*|*"git pull"*|*"git merge"*|*"git rebase"*|*"git reset"*|*"git clean"*) block "mutating Git operation" ;;
  *"git remote add"*|*"git remote remove"*|*"git remote rename"*|*"git remote set-url"*) block "remote alteration" ;;
  *"git branch -d"*|*"git branch -D"*|*"git branch --delete"*|*"git tag -d"*|*"git tag -D"*|*"git tag --delete"*|*"git tag -a"*|*"git tag -s"*) block "destructive branch or tag operation" ;;
  *"gh pr create"*|*"gh pr edit"*|*"gh pr close"*|*"gh pr merge"*|*"gh pr comment"*|*"gh issue create"*|*"gh issue edit"*|*"gh issue close"*|*"gh issue comment"*|*"gh issue delete"*) block "outward GitHub operation" ;;
  *"gh label create"*|*"gh label edit"*|*"gh label delete"*|*"gh release create"*|*"gh release edit"*|*"gh release delete"*|*"gh workflow run"*|*"gh repo delete"*|*"gh repo edit"*) block "outward GitHub operation" ;;
  *"gh api"*"--method POST"*|*"gh api"*"--method PUT"*|*"gh api"*"--method PATCH"*|*"gh api"*"--method DELETE"*|*"gh api"*"-X POST"*|*"gh api"*"-X PUT"*|*"gh api"*"-X PATCH"*|*"gh api"*"-X DELETE"*) block "non-GET GitHub API operation" ;;
  *"rm -rf /"*|*"rm -rf ~"*|*"rm -rf \$HOME"*) block "recursive delete of root or home path" ;;
  *"curl"*"| sh"*|*"curl"*"| bash"*|*"wget"*"| sh"*) block "piping a network download into a shell" ;;
  *"mkfs."*|*" dd if="*"of=/dev/"*) block "raw disk write" ;;
esac
exit 0
