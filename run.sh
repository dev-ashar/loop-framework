#!/usr/bin/env bash
# LOOPS runner — bootstrap a loop's state dir in the current project, then hand
# off to a native primitive. Keeps state on disk so a crashed run is recoverable.
#
#   ./run.sh init                 # create .loops/ from templates
#   ./run.sh init "<goal>"        # init and seed the contract goal
#   ./run.sh status               # show contract + progress + tail of log
#
# After `init`, drive the loop with the native primitives:
#   /contract   negotiate acceptance criteria into .loops/contract.md
#   /goal ...   run a measurable loop with a stop condition
#   /loop 5m .. run on an interval

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
LOOPDIR=".loops"

cmd="${1:-status}"

case "$cmd" in
  init)
    mkdir -p "$LOOPDIR"
    for f in contract.md progress.md log.md feature_list.json; do
      if [ ! -f "$LOOPDIR/$f" ]; then
        cp "$TEMPLATES/$f" "$LOOPDIR/$f"
        echo "created $LOOPDIR/$f"
      else
        echo "kept $LOOPDIR/$f (already exists)"
      fi
    done
    if [ -n "${2:-}" ]; then
      # Seed the goal line in the fresh contract.
      tmp="$(mktemp)"
      awk -v g="$2" 'BEGIN{done=0} /^<one sentence/ && !done {print g; done=1; next} {print}' \
        "$LOOPDIR/contract.md" > "$tmp" && mv "$tmp" "$LOOPDIR/contract.md"
      echo "seeded goal: $2"
    fi
    echo "Next: run /contract to negotiate acceptance criteria."
    ;;
  status)
    [ -d "$LOOPDIR" ] || { echo "No .loops/ here. Run: $0 init"; exit 0; }
    echo "=== contract.md ==="; sed -n '1,20p' "$LOOPDIR/contract.md" 2>/dev/null || true
    echo; echo "=== progress.md ==="; sed -n '1,20p' "$LOOPDIR/progress.md" 2>/dev/null || true
    echo; echo "=== log.md (tail) ==="; tail -n 10 "$LOOPDIR/log.md" 2>/dev/null || true
    ;;
  score)
    subcmd="${2:-}"
    case "$subcmd" in
      record)
        [ $# -eq 5 ] || { echo "usage: $0 score record <iter> <score> <verdict>"; exit 1; }
        iter="$3"
        score="$4"
        verdict="$5"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        entry=$(jq -n --arg i "$iter" --arg s "$score" --arg v "$verdict" --arg t "$ts" \
          '{iteration: ($i | tonumber), score: ($s | tonumber), verdict: $v, ts: $t}')
        tmp="$(mktemp)"
        jq --argjson entry "$entry" '.metric.history += [$entry]' "$LOOPDIR/feature_list.json" > "$tmp"
        mv "$tmp" "$LOOPDIR/feature_list.json"
        ;;
      stall)
        history_len=$(jq '.metric.history | length' "$LOOPDIR/feature_list.json")
        if [ "$history_len" -lt 2 ]; then
          exit 0
        fi
        last=$(jq '.metric.history[-1].score' "$LOOPDIR/feature_list.json")
        prev=$(jq '.metric.history[-2].score' "$LOOPDIR/feature_list.json")
        # Non-increasing: last <= prev
        if awk -v l="$last" -v p="$prev" 'BEGIN {exit !(l <= p)}'; then
          echo "STALL"
          exit 2
        fi
        exit 0
        ;;
      *)
        echo "usage: $0 score {record <iter> <score> <verdict> | stall}"; exit 1
        ;;
    esac
    ;;
  reap)
    [ -d "$LOOPDIR" ] || { echo "No .loops/ here. Run: $0 init"; exit 0; }
    if [ ! -f "$LOOPDIR/.running" ]; then
      exit 0
    fi
    # Read-only check: never delete, move, or truncate .running
    # Check if .running is stale (>48h old)
    running_mtime=$(stat -f %m "$LOOPDIR/.running" 2>/dev/null || echo 0)
    now=$(date +%s)
    age_hours=$(( (now - running_mtime) / 3600 ))

    if [ "$age_hours" -lt 48 ]; then
      exit 0
    fi

    # Check last verdict in history
    history_len=$(jq '.metric.history | length' "$LOOPDIR/feature_list.json" 2>/dev/null || echo 0)
    if [ "$history_len" -gt 0 ]; then
      last_verdict=$(jq -r '.metric.history[-1].verdict' "$LOOPDIR/feature_list.json" 2>/dev/null || echo "")
      if [ "$last_verdict" = "PASS" ]; then
        echo "AWAITING LANDING APPROVAL"
        exit 0
      fi
    fi

    echo "STALE"
    exit 1
    ;;
  lint)
    target="${2:-.loops/contract.md}"
    [ -f "$target" ] || { echo "lint: $target not found"; exit 1; }

    errors=0
    basename_target=$(basename "$target")

    if [ "$basename_target" = "log.md" ]; then
      # Log format validation (criterion 13)
      while IFS=: read -r linenum line; do
        [ -n "$linenum" ] || continue
        if ! echo "$line" | grep -Eq '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] .+ \| .+$'; then
          echo "lint: $target line $linenum malformed: $line"
          errors=$((errors + 1))
        fi
      done < <(grep -n '^## \[' "$target")
    else
      # Contract structure validation (criterion 9)
      # Check required headings
      if ! grep -q '^## Goal$' "$target"; then
        echo "lint: missing '## Goal' heading"
        errors=$((errors + 1))
      fi
      if ! grep -q '^## Constraints$' "$target"; then
        echo "lint: missing '## Constraints' heading"
        errors=$((errors + 1))
      fi
      if ! grep -q '^## Acceptance criteria$' "$target"; then
        echo "lint: missing '## Acceptance criteria' heading"
        errors=$((errors + 1))
      fi
      if ! grep -q '^## Verify' "$target"; then
        echo "lint: missing '## Verify' heading"
        errors=$((errors + 1))
      else
        # Check for fenced code block in Verify section
        verify_start=$(grep -n '^## Verify' "$target" | head -1 | cut -d: -f1)
        next_section=$(awk -v start="$verify_start" 'NR > start && /^## / {print NR; exit}' "$target")
        if [ -z "$next_section" ]; then
          verify_content=$(awk -v start="$verify_start" 'NR > start' "$target")
        else
          verify_content=$(awk -v start="$verify_start" -v end="$next_section" 'NR > start && NR < end' "$target")
        fi
        if ! echo "$verify_content" | grep -q '^```'; then
          echo "lint: '## Verify' section has no fenced code block"
          errors=$((errors + 1))
        fi
      fi

      # Check acceptance criteria section format
      criteria_start=$(grep -n '^## Acceptance criteria$' "$target" | head -1 | cut -d: -f1)
      if [ -n "$criteria_start" ]; then
        next_section=$(awk -v start="$criteria_start" 'NR > start && /^## / {print NR; exit}' "$target")
        if [ -z "$next_section" ]; then
          end_line=$(wc -l < "$target")
        else
          end_line=$((next_section - 1))
        fi

        awk -v start="$criteria_start" -v end="$end_line" 'NR > start && NR <= end {
          if (NF == 0) next;  # Skip blank lines
          if (/^#{2,4} /) next;  # Heading
          if (/^> /) next;  # Blockquote
          if (/^- \[[ x]\] /) next;  # Checkbox item
          if (/^  /) next;  # Continuation line (indented >=2 spaces)
          print "lint: line " NR " in acceptance criteria is bare prose: " $0
          exit 1
        }' "$target" || errors=$((errors + 1))
      fi
    fi

    [ "$errors" -eq 0 ] && exit 0 || exit 1
    ;;
  log)
    [ $# -eq 3 ] || { echo "usage: $0 log \"<op>\" \"<title>\""; exit 1; }
    op="$2"
    title="$3"
    ts=$(date +"%Y-%m-%d %H:%M")
    echo "## [$ts] $op | $title" >> "$LOOPDIR/log.md"
    ;;
  multireport)
    shift  # Remove 'multireport' from args
    for repo in "$@"; do
      [ -d "$repo" ] || { echo "SKIP: $repo not found"; continue; }

      # Worktree count
      wt_count=$(git -C "$repo" worktree list 2>/dev/null | wc -l | tr -d ' ')

      # Dirty file count
      dirty_count=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

      # .running state
      if [ -f "$repo/.loops/.running" ]; then
        running_state="present"
      else
        running_state="absent"
      fi

      # Log format ok
      log_ok="n/a"
      if [ -f "$repo/.loops/log.md" ]; then
        log_ok="y"
        if grep -q '^## \[' "$repo/.loops/log.md"; then
          while IFS= read -r line; do
            if ! echo "$line" | grep -Eq '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] .+ \| .+$'; then
              log_ok="n"
              break
            fi
          done < <(grep '^## \[' "$repo/.loops/log.md")
        fi
      fi

      echo "$repo: wt=$wt_count dirty=$dirty_count running=$running_state log_ok=$log_ok"

      # Check for bypass shape: log.md with entries but no contract.md
      if [ -f "$repo/.loops/log.md" ] && [ ! -f "$repo/.loops/contract.md" ]; then
        entry_count=$(grep -c '^## \[' "$repo/.loops/log.md" 2>/dev/null || echo 0)
        if [ "$entry_count" -gt 0 ]; then
          echo "WARN: no contract.md"
        fi
      fi
    done
    exit 0
    ;;
  *)
    echo "usage: $0 {init [\"goal\"] | status | score {record|stall} | reap | lint [path] | log \"<op>\" \"<title>\" | multireport <repo-path>...}"
    exit 1
    ;;
esac
