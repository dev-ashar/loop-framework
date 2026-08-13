#!/usr/bin/env bash

# Durable memory, distinct from `.loops/` in one way that matters: `.loops/progress.md`
# is the current iteration's scratch and is overwritten every pass, while this
# survives across days and branches. Two files, two lifetimes:
#
#   repo.md            curated facts true of this repo regardless of branch
#   branches/<slug>.md append-only trace of one piece of work
#
# Both untracked. They exist so an agent starting cold does not re-derive what a
# previous run already learned or already ruled out.

# All worktrees of a repo share one store. `--git-common-dir` is the main repo's
# .git even from inside a linked worktree, where `--git-dir` is not.
mem_dir() {
  local common
  if ! common=$(git rev-parse --git-common-dir 2>/dev/null); then
    printf 'loops: not a git repository\n' >&2
    return 1
  fi
  case "$common" in
    /*) ;;
    *) common="$PWD/$common" ;;
  esac
  printf '%s/.loops-mem\n' "$(dirname "$common")"
}

# Branch names contain slashes; file names cannot.
mem_branch_slug() {
  local branch
  if ! branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
    printf 'loops: not a git repository\n' >&2
    return 1
  fi
  if [ "$branch" = HEAD ]; then
    branch="detached-$(git rev-parse --short HEAD)"
  fi
  printf '%s\n' "$branch" | tr '/' '-'
}

mem_append() {
  local path="$1" text="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "- [$(date -u +%Y-%m-%d)] $text" >> "$path"
}

cmd_mem() {
  local subcommand="${1-}"
  shift || true
  local dir slug repo_file branch_file
  if ! dir=$(mem_dir); then return 1; fi
  repo_file="$dir/repo.md"

  case "$subcommand" in
    show)
      # The whole store, capped. Meant to be cheap enough to inject on every
      # session start; an uncapped journal would poison the context window.
      local limit="${1:-20}"
      case "$limit" in
        ''|*[!0-9]*) printf 'usage: cmd_mem show [journal-entry-limit]\n' >&2; return 2 ;;
      esac
      if ! slug=$(mem_branch_slug); then return 1; fi
      branch_file="$dir/branches/$slug.md"
      if [ ! -f "$repo_file" ] && [ ! -f "$branch_file" ]; then
        return 0
      fi
      if [ -f "$repo_file" ]; then
        printf '## repo facts (%s)\n' "$repo_file"
        cat "$repo_file"
      fi
      if [ -f "$branch_file" ]; then
        printf '\n## branch journal: %s (last %s)\n' "$slug" "$limit"
        tail -n "$limit" "$branch_file"
      fi
      ;;

    note)
      local text="${1-}"
      if [ -z "$text" ]; then
        printf 'usage: cmd_mem note "<what you did, tried, or ruled out>"\n' >&2
        return 2
      fi
      if ! slug=$(mem_branch_slug); then return 1; fi
      mem_append "$dir/branches/$slug.md" "$text"
      printf 'noted on %s\n' "$slug"
      ;;

    fact)
      local text="${1-}"
      if [ -z "$text" ]; then
        printf 'usage: cmd_mem fact "<something true of this repo on any branch>"\n' >&2
        return 2
      fi
      mem_append "$repo_file" "$text"
      printf 'recorded in %s\n' "$repo_file"
      ;;

    path)
      printf '%s\n' "$dir"
      ;;

    reap)
      # A journal for a branch that no longer exists is debris.
      local file branch reaped=0
      [ -d "$dir/branches" ] || return 0
      for file in "$dir"/branches/*.md; do
        [ -f "$file" ] || continue
        branch=${file##*/}
        branch=${branch%.md}
        case "$branch" in detached-*) continue ;; esac
        # The slug is lossy: feat/x and feat-x collapse. Keep the journal unless
        # no branch could have produced it.
        if git branch --format='%(refname:short)' \
          | tr '/' '-' | grep -qxF "$branch"; then
          continue
        fi
        rm -f "$file"
        printf 'reaped %s\n' "$branch"
        reaped=$((reaped + 1))
      done
      [ "$reaped" -eq 0 ] && return 0 || return 0
      ;;

    *)
      printf 'usage: cmd_mem {show [limit]|note "<text>"|fact "<text>"|path|reap}\n' >&2
      return 2
      ;;
  esac
}
