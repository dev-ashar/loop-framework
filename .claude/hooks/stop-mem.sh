#!/usr/bin/env bash
# Stop: nudge the agent to record changed work before a clean exit.
# Exit 2 feeds stderr back to the agent. Write the marker before exit so refusal
# cannot loop. Memory must never break a session.

set -uo pipefail

[ "${LOOPS_MEM_NUDGE:-}" = 0 ] && exit 0
common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
command -v loops >/dev/null 2>&1 || exit 0
case "$common" in
  /*) ;;
  *) common="$PWD/$common" ;;
esac
dir="$(dirname "$common")/.loops-mem"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
if [ "$branch" = HEAD ]; then
  short=$(git rev-parse --short HEAD 2>/dev/null) || exit 0
  branch="detached-$short"
fi
slug=$(printf '%s\n' "$branch" | tr '/' '-')
today=$(date -u +%Y-%m-%d)
marker="$dir/.nudged-$slug-$today"
[ -e "$marker" ] && exit 0

work=0
[ -n "$(git status --porcelain 2>/dev/null)" ] && work=1
[ -n "$(git log --since=midnight -1 --format=%H HEAD 2>/dev/null)" ] && work=1
[ "$work" -eq 1 ] || exit 0
journal="$dir/branches/$slug.md"
grep -q "^- \[$today\]" "$journal" 2>/dev/null && exit 0

mkdir -p "$dir"
: > "$marker"
printf 'Record one note before stopping: run `loops mem note "<one line: what you did or ruled out>"`, then stop.\n' >&2
exit 2
