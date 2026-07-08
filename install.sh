#!/usr/bin/env bash
# LOOPS installer — wires this kit into ~/.claude, backup-first and idempotent.
#
#   ./install.sh            # install (backs up first)
#   ./install.sh --dry-run  # print every action, change nothing
#
# What it does:
#   1. Backs up ~/.claude/{CLAUDE.md,settings.json,agents,skills} to a timestamped dir.
#   2. Symlinks this kit's agents, skills, hooks, and CLAUDE.md into ~/.claude.
#   3. MERGES settings.json (keeps model, plugins, marketplaces, rtk hook; adds
#      the loops hooks; drops the retired flow-goal hook). Never clobbers plugins.
#   4. Retires (unlinks only — sources untouched) flow, autoresearch, grill-me,
#      and the old reviewer agent. Keeps handoff and jaljira.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$SCRIPT_DIR/.claude"
DEST="$HOME/.claude"
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP="$DEST/backups/pre-loops-$STAMP"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { printf '  %s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

echo "LOOPS installer  (kit: $KIT  →  dest: $DEST)"
[ "$DRY" = 1 ] && echo "*** DRY RUN — no changes will be made ***"
echo

# ---------------------------------------------------------------- preflight
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required for the settings merge."; exit 1; }
[ -d "$KIT" ] || { echo "ERROR: kit dir not found: $KIT"; exit 1; }
run "mkdir -p '$DEST/agents' '$DEST/skills' '$DEST/hooks'"

# ---------------------------------------------------------------- 1. backup
echo "1. Backing up current config → $BACKUP"
run "mkdir -p '$BACKUP'"
for item in CLAUDE.md settings.json agents skills; do
  if [ -e "$DEST/$item" ]; then
    run "cp -R '$DEST/$item' '$BACKUP/' 2>/dev/null || true"
    say "backed up $item"
  fi
done
echo

# ---------------------------------------------------------------- 2. agents
echo "2. Linking agents"
for f in "$KIT"/agents/*.md; do
  name="$(basename "$f")"
  run "ln -sfn '$f' '$DEST/agents/$name'"
  say "→ agents/$name"
done
# Retire the old diff-linter reviewer (superseded by the adversarial evaluator).
if [ -e "$DEST/agents/reviewer.md" ]; then
  run "rm -f '$DEST/agents/reviewer.md'"
  say "retired agents/reviewer.md (backed up)"
fi
echo

# ---------------------------------------------------------------- 3. skills
echo "3. Linking skills"
for d in "$KIT"/skills/*/; do
  name="$(basename "$d")"
  run "ln -sfn '${d%/}' '$DEST/skills/$name'"
  say "→ skills/$name"
done
# Retire superseded skills (unlink only — sources remain in ~/.agents/skills).
for old in flow autoresearch grill-me; do
  if [ -L "$DEST/skills/$old" ] || [ -e "$DEST/skills/$old" ]; then
    run "rm -f '$DEST/skills/$old'"
    say "retired skills/$old (source untouched)"
  fi
done
say "kept: handoff, jaljira-jira-docs"
echo

# ---------------------------------------------------------------- 4. hooks
echo "4. Linking hooks"
for f in "$KIT"/hooks/*.sh; do
  name="$(basename "$f")"
  run "chmod +x '$f'"
  run "ln -sfn '$f' '$DEST/hooks/$name'"
  say "→ hooks/$name"
done
say "kept: rtk-rewrite.sh (if present)"
echo

# ---------------------------------------------------------------- 5. CLAUDE.md
echo "5. Installing thin CLAUDE.md (RTK + memory preserved via includes)"
run "ln -sfn '$KIT/CLAUDE.md' '$DEST/CLAUDE.md'"
say "→ CLAUDE.md"
echo

# ---------------------------------------------------------------- 6. settings merge
echo "6. Merging settings.json (plugins/marketplaces/rtk preserved)"
EXISTING="$DEST/settings.json"
[ -f "$EXISTING" ] || echo '{}' > "${EXISTING}.loops-empty-tmp" 2>/dev/null || true
SRC="$EXISTING"; [ -f "$EXISTING" ] || SRC="${EXISTING}.loops-empty-tmp"

MERGE_JQ='
  .[0] as $e | .[1] as $k |
  $e
  | .model = $k.model
  | .effortLevel = ($e.effortLevel // $k.effortLevel)
  | .hooks = ($e.hooks // {})
  | .hooks.PreToolUse  = ( (($e.hooks.PreToolUse  // []) | map(select([.hooks[].command] | any(test("pre-tool-use.sh"))  | not))) + $k.hooks.PreToolUse )
  | .hooks.PostToolUse = ( (($e.hooks.PostToolUse // []) | map(select([.hooks[].command] | any(test("post-tool-use.sh")) | not))) + $k.hooks.PostToolUse )
  | .hooks.Stop        = ( (($e.hooks.Stop        // []) | map(select([.hooks[].command] | any(test("stop.sh"))          | not))) + $k.hooks.Stop )
  | del(.hooks.UserPromptSubmit | select(. == null))
'
# Drop the retired flow-goal UserPromptSubmit injector if it is the only UPS hook.
DROP_FLOWGOAL='if (.hooks.UserPromptSubmit // []) | all(([.hooks[].command] | join(" ")) | test("flow-goal")) then del(.hooks.UserPromptSubmit) else . end'

if [ "$DRY" = 1 ]; then
  say "[dry-run] would merge $KIT/settings.json into $EXISTING; preview:"
  jq -s "$MERGE_JQ | $DROP_FLOWGOAL" "$SRC" "$KIT/settings.json" 2>/dev/null | sed 's/^/      /' || say "(merge preview failed — check jq)"
else
  TMP="$(mktemp)"
  jq -s "$MERGE_JQ | $DROP_FLOWGOAL" "$SRC" "$KIT/settings.json" > "$TMP"
  mv "$TMP" "$EXISTING"
  say "merged → settings.json"
fi
rm -f "${EXISTING}.loops-empty-tmp" 2>/dev/null || true
echo

# ---------------------------------------------------------------- done
echo "Done. Backup at: $BACKUP"
echo "Verify with:  ls -la $DEST/agents $DEST/skills $DEST/hooks"
echo "Restore with: cp -R $BACKUP/* $DEST/"
