#!/usr/bin/env bash
# Install LOOPS into the current user's Claude configuration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KIT="$SCRIPT_DIR/.claude"
DEST="${HOME:?}/.claude"
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP="$DEST/backups/pre-loops-$STAMP"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { printf '  %s\n' "$*"; }
managed=(CLAUDE.md settings.json agents skills hooks output-styles)

require_sources() {
  local f d
  [ -d "$KIT" ] || { echo "ERROR: kit dir not found: $KIT" >&2; return 1; }
  [ -f "$KIT/settings.json" ] || { echo "ERROR: required source missing: $KIT/settings.json" >&2; return 1; }
  [ -f "$KIT/CLAUDE.md" ] || { echo "ERROR: required source missing: $KIT/CLAUDE.md" >&2; return 1; }
  [ -d "$KIT/agents" ] && [ -n "$(find "$KIT/agents" -maxdepth 1 -name '*.md' -print -quit)" ] || { echo "ERROR: required agent sources missing" >&2; return 1; }
  [ -d "$KIT/skills" ] && [ -n "$(find "$KIT/skills" -mindepth 1 -maxdepth 1 -type d -print -quit)" ] || { echo "ERROR: required skill sources missing" >&2; return 1; }
  [ -d "$KIT/hooks" ] && [ -n "$(find "$KIT/hooks" -maxdepth 1 -name '*.sh' -print -quit)" ] || { echo "ERROR: required hook sources missing" >&2; return 1; }
  [ -d "$KIT/output-styles" ] && [ -n "$(find "$KIT/output-styles" -maxdepth 1 -name '*.md' -print -quit)" ] || { echo "ERROR: required output-style sources missing" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo 'ERROR: jq is required for the settings merge.' >&2; return 1; }
}

merge_settings() {
  local existing="$1" output="$2" kit="$KIT/settings.json"
  jq -s '
    .[0] as $e | .[1] as $k |
    $e | .model = $k.model | .effortLevel = $k.effortLevel | .outputStyle = $k.outputStyle
    | .hooks = ($e.hooks // {})
    | .hooks.PreToolUse = (($e.hooks.PreToolUse // []) | map(select(([.hooks[].command] | any(test("pre-tool-use.sh"))) | not)) + (($k.hooks.PreToolUse // []) | map(.hooks |= map(if .command == "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-use.sh" then .command = "$HOME/.claude/hooks/pre-tool-use.sh" else . end))))
    | .hooks.PostToolUse = (($e.hooks.PostToolUse // []) | map(select(([.hooks[].command] | any(test("post-tool-use.sh"))) | not)))
    | if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end
    | .hooks.Stop = (($e.hooks.Stop // []) | map(select(([.hooks[].command] | any(test("stop.sh|stop-mem.sh"))) | not)) + ($k.hooks.Stop // []))
    | .hooks.SessionStart = (($e.hooks.SessionStart // []) | map(select(([.hooks[].command] | any(test("session-start-mem.sh"))) | not)) + ($k.hooks.SessionStart // []))
    | .permissions = ($e.permissions // {})
  | .permissions.allow = (($e.permissions.allow // []) + ($k.permissions.allow // []) | unique)
    | if (.hooks.UserPromptSubmit // []) | all(([.hooks[].command] | join(" ")) | test("flow-goal")) then del(.hooks.UserPromptSubmit) else . end
  ' "$existing" "$kit" > "$output"
  jq empty "$output"
}

printf 'LOOPS installer  (kit: %s  ->  dest: %s)\n' "$KIT" "$DEST"
if [ "$DRY" = 1 ]; then
  before_root=$(mktemp -d)
  cp -a "$HOME"/.claude "$before_root/claude" 2>/dev/null || true
  cp -a "$HOME"/.local "$before_root/local" 2>/dev/null || true
  trap 'rm -rf "$before_root"' EXIT
fi
[ "$DRY" = 1 ] && printf '%s\n' '*** DRY RUN - no changes will be made ***'
require_sources

# Reject malformed existing settings before creating backups or replacing paths.
if [ -e "$DEST/settings.json" ] || [ -L "$DEST/settings.json" ]; then
  jq empty "$DEST/settings.json" >/dev/null 2>&1 || { echo 'ERROR: existing settings.json is malformed; no managed paths replaced' >&2; exit 1; }
fi

printf '%s\n' '1. Backup managed paths'
for item in "${managed[@]}"; do
  if [ -e "$DEST/$item" ] || [ -L "$DEST/$item" ]; then say "backup $DEST/$item -> $BACKUP/$item"; else say "no existing $DEST/$item"; fi
done
printf '%s\n' '2. Merge settings and preserve unrelated entries'
say "merge $KIT/settings.json -> $DEST/settings.json"
printf '%s\n' '3. Link agents, skills, hooks, and CLAUDE.md'
for f in "$KIT"/agents/*.md; do say "link $DEST/agents/$(basename "$f")"; done
for d in "$KIT"/skills/*/; do say "link $DEST/skills/$(basename "${d%/}")"; done
for f in "$KIT"/hooks/*.sh; do say "link $DEST/hooks/$(basename "$f")"; done
for f in "$KIT"/output-styles/*.md; do say "link $DEST/output-styles/$(basename "$f")"; done
say "link $DEST/CLAUDE.md"
printf '%s\n' '4. Preserve or create lessons store'
say "preserve/create $DEST/memory/lessons.jsonl"
printf '%s\n' '5. Link CLI'
say "ln -sfn '$SCRIPT_DIR/run.sh' '$HOME/.local/bin/loops'"
[ "$DRY" = 1 ] && exit 0

mkdir -p "$DEST" "$DEST/backups" "$DEST/agents" "$DEST/skills" "$DEST/hooks" "$DEST/output-styles" "$HOME/.local/bin"
mkdir -p "$BACKUP"
for item in "${managed[@]}"; do
  if [ -e "$DEST/$item" ] || [ -L "$DEST/$item" ]; then cp -a "$DEST/$item" "$BACKUP/$item"; fi
done
rollback() {
  local item
  for item in "${managed[@]}"; do rm -rf "$DEST/$item"; [ -e "$BACKUP/$item" ] || [ -L "$BACKUP/$item" ] && cp -a "$BACKUP/$item" "$DEST/$item" || true; done
  rm -f "$HOME/.local/bin/loops"
  [ -e "$BACKUP/.loops-cli" ] && cp -a "$BACKUP/.loops-cli" "$HOME/.local/bin/loops" || true
}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then rollback; fi; exit "$rc"' EXIT

# Validate and stage settings before replacing any managed path.
tmp_settings=$(mktemp "$DEST/.settings.XXXXXX")
existing_settings="${DEST}/settings.json"
created_empty_settings=0
if [ ! -e "$existing_settings" ] && [ ! -L "$existing_settings" ]; then
  existing_settings=$(mktemp "$DEST/.existing-settings.XXXXXX")
  printf '{}\n' > "$existing_settings"
  created_empty_settings=1
fi
merge_settings "$existing_settings" "$tmp_settings" 2>/dev/null || { rm -f "$tmp_settings"; [ "$created_empty_settings" = 1 ] && rm -f "$existing_settings"; echo 'ERROR: settings merge failed; no managed paths replaced' >&2; exit 1; }
[ "$created_empty_settings" = 1 ] && rm -f "$existing_settings"
mv -f "$tmp_settings" "$DEST/settings.json"
for f in "$KIT"/agents/*.md; do ln -sfn "$f" "$DEST/agents/$(basename "$f")"; done
for d in "$KIT"/skills/*/; do ln -sfn "${d%/}" "$DEST/skills/$(basename "${d%/}")"; done
for f in "$KIT"/hooks/*.sh; do chmod +x "$f"; ln -sfn "$f" "$DEST/hooks/$(basename "$f")"; done
for f in "$KIT"/output-styles/*.md; do ln -sfn "$f" "$DEST/output-styles/$(basename "$f")"; done
ln -sfn "$KIT/CLAUDE.md" "$DEST/CLAUDE.md"
for old in flow autoresearch grill-me; do rm -f "$DEST/skills/$old"; done
# Keep current role projections, including planner, across reinstall.
for old in builder evaluator field-guide general-purpose; do rm -f "$DEST/agents/$old.md"; done
mkdir -p "$DEST/memory"
[ -e "$DEST/memory/lessons.jsonl" ] || : > "$DEST/memory/lessons.jsonl"
if [ -e "$HOME/.local/bin/loops" ] && [ ! -L "$HOME/.local/bin/loops" ]; then cp -a "$HOME/.local/bin/loops" "$BACKUP/.loops-cli"; fi
ln -sfn "$SCRIPT_DIR/run.sh" "$HOME/.local/bin/loops"
trap - EXIT
printf 'Done. Backup at: %s\n' "$BACKUP"
