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

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  LINK="$(readlink "$SOURCE")"
  case "$LINK" in
    /*) SOURCE="$LINK" ;;
    *) SOURCE="$SOURCE_DIR/$LINK" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
LOOPDIR=".loops"
LESSONS_FILE="$HOME/.claude/memory/lessons.jsonl"

# Stopword list for `lesson check`'s tokenizer (criterion 18): closed-class
# English function words only — deliberately NOT domain nouns/verbs (those are
# the actual match signal). Space-padded so `is_stopword` does a whole-word
# substring test.
STOPWORDS=" a an the is are was were be been being to of and or in on at for with from by as that this these those it its into over under about if then so but not no nor do does did doesnt dont didnt has have had will would can could should shall may might must i you he she they we us my your his her their our them him "

is_stopword() {
  case "$STOPWORDS" in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Tokenize free text: lowercase, split on non-alphanumerics, drop stopwords and
# single-character noise, de-dupe. Prints space-separated unique tokens.
lesson_tokens() {
  local text="$1" raw tok result=""
  raw="$(printf '%s' "$text" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' ' ')"
  for tok in $raw; do
    [ ${#tok} -ge 2 ] || continue
    is_stopword "$tok" && continue
    case " $result " in
      *" $tok "*) ;;
      *) result="$result $tok" ;;
    esac
  done
  printf '%s' "${result# }"
}

current_model_for_role() {
  local role="$1" agents_dir="${LOOPS_AGENTS_DIR:-$SCRIPT_DIR/.claude/agents}"
  awk '
    NR == 1 { line=$0; sub(/\r$/, "", line); if (line == "---") in_front=1; next }
    { line=$0; sub(/\r$/, "", line) }
    in_front && line == "---" { exit }
    in_front && line ~ /^[[:space:]]*model:[[:space:]]*/ {
      sub(/^[[:space:]]*model:[[:space:]]*/, "", line); print line; exit
    }
  ' "$agents_dir/$role.md" 2>/dev/null
}

ui_roster() {
  local agents_dir="${LOOPS_AGENTS_DIR:-$SCRIPT_DIR/.claude/agents}" path role model engine='claude' binary
  for path in "$agents_dir"/*.md; do
    [ -f "$path" ] || continue
    role=${path##*/}; role=${role%.md}; model=$(current_model_for_role "$role")
    printf '%-12s %s\n' "$role" "${model:-(default)}"
  done
  if [ -f "$LOOPDIR/engine" ]; then
    engine=$(cat "$LOOPDIR/engine" 2>/dev/null || printf '%s' claude)
  fi
  binary=$(command -v "$engine" 2>/dev/null || printf '%s' '(missing)')
  printf '%-12s %s\n' engine "$engine ($binary)"
}

ui_config() {
  local roster selected status role current options choice new_model engine current_engine engine_choice FZF
  local claude_path opencode_path confirm
  if [ ! -t 0 ]; then
    printf 'loops: interactive configuration requires a TTY; use loops models set <role> <model>\n' >&2
    return 1
  fi
  # LOOPS_FZF is the seam: it lets this check be exercised, and lets an fzf that
  # is not on PATH be pointed at directly.
  FZF="${LOOPS_FZF:-fzf}"
  if ! command -v "$FZF" >/dev/null 2>&1; then
    printf 'loops: the interactive UI needs fzf (brew install fzf); use loops models set <role> <model>\n' >&2
    return 1
  fi
  . "$SCRIPT_DIR/lib/models.sh"
  . "$SCRIPT_DIR/lib/engine.sh"
  roster=$(ui_roster)
  if selected=$(printf '%s\n' "$roster" | "$FZF" --prompt='configure> ' --header='Select a role or engine' --height=40% --no-multi --layout=reverse --preview="printf '%s\\n' '$roster'"); then
    :
  else
    status=$?
    return "$status"
  fi
  role=$(printf '%s\n' "$selected" | awk '{print $1}')
  if [ "$role" = engine ]; then
    current_engine=claude
    [ -f "$LOOPDIR/engine" ] && current_engine=$(cat "$LOOPDIR/engine" 2>/dev/null || printf '%s' claude)
    claude_path=$(command -v claude 2>/dev/null || true)
    opencode_path=$(command -v opencode 2>/dev/null || true)
    engine_choice=''
    [ -n "$claude_path" ] && engine_choice="${engine_choice}$( [ "$current_engine" = claude ] && printf '> ' || printf '  ')claude\\t$claude_path\\n"
    [ -n "$opencode_path" ] && engine_choice="${engine_choice}$( [ "$current_engine" = opencode ] && printf '> ' || printf '  ')opencode\\t$opencode_path\\n"
    if [ -z "$engine_choice" ]; then printf 'loops: no engine binaries found\n' >&2; return 1; fi
    if engine_choice=$(printf '%b' "$engine_choice" | "$FZF" --prompt='engine> ' --header='Choose engine' --height=30% --no-multi --layout=reverse --preview="printf '%s\\n' '$roster'"); then :; else status=$?; return "$status"; fi
    engine=$(printf '%s\n' "$engine_choice" | awk '{print $1}')
    [ "$engine" = "$current_engine" ] && return 0
    printf 'engine: %s -> %s\n' "$current_engine" "$engine"
    printf 'Apply change? [y/N] '
    IFS= read -r confirm || return 1
    case "$confirm" in y|Y) cmd_engine set "$engine" ;; *) return 1 ;; esac
    return $?
  fi
  current=$(current_model_for_role "$role")
  if ! options=$(models_menu_options "$current"); then return 1; fi
  if choice=$(printf '%s\n' "$options" | "$FZF" --prompt="$role> " --header="Choose model for $role" --height=50% --no-multi --layout=reverse --preview="printf '%s\\n' '$roster'"); then :; else status=$?; return "$status"; fi
  new_model=$(printf '%s\n' "$choice" | awk -F '\t' '{print $2}')
  [ -n "$new_model" ] && [ "$new_model" != "$current" ] || return 0
  printf '%s: %s -> %s\n' "$role" "$current" "$new_model"
  printf 'Apply change? [y/N] '
  IFS= read -r confirm || return 1
  case "$confirm" in y|Y) cmd_models set "$role" "$new_model" ;; *) return 1 ;; esac
}

cmd="${1:-ui}"

case "$cmd" in
  ui)
    ui_config
    ;;
  init)
    mkdir -p "$LOOPDIR"
    for f in contract.md progress.md log.md feature_list.json; do
      if [ ! -f "$LOOPDIR/$f" ]; then
        if ! cp "$TEMPLATES/$f" "$LOOPDIR/$f"; then
          echo "failed to create $LOOPDIR/$f" >&2
          exit 1
        fi
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
        # A loop that has reached PASS is finished, not stuck. Flat scores at the
        # ceiling are the stop condition; only flat scores below it are a stall.
        last_verdict=$(jq -r '.metric.history[-1].verdict' "$LOOPDIR/feature_list.json")
        if [ "$last_verdict" = "PASS" ]; then
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
          if (/^[0-9]+\. /) next;  # Numbered criterion
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
  lesson)
    subcmd="${2:-}"
    case "$subcmd" in
      record)
        shift 2
        category="" mistake="" correction="" source_path=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --category) category="$2"; shift 2 ;;
            --mistake) mistake="$2"; shift 2 ;;
            --correction) correction="$2"; shift 2 ;;
            --source) source_path="$2"; shift 2 ;;
            *) echo "unknown arg: $1"; exit 1 ;;
          esac
        done
        [ -n "$category" ] && [ -n "$mistake" ] && [ -n "$correction" ] || {
          echo "usage: $0 lesson record --category <cat> --mistake \"<t>\" --correction \"<t>\" [--source <path>]"
          exit 1
        }
        mkdir -p "$(dirname "$LESSONS_FILE")"
        [ -f "$LESSONS_FILE" ] || touch "$LESSONS_FILE"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        entry="$(jq -nc \
          --arg category "$category" \
          --arg mistake "$mistake" \
          --arg correction "$correction" \
          --arg source_path "$source_path" \
          --arg ts "$ts" \
          '{category: $category, mistake: $mistake, correction: $correction, source: $source_path, ts: $ts}')"
        printf '%s\n' "$entry" >> "$LESSONS_FILE"
        ;;
      check)
        query="${3:-}"
        [ -n "$query" ] || {
          echo "usage: $0 lesson check \"<free text>\""
          exit 1
        }
        [ -f "$LESSONS_FILE" ] || exit 1
        q_tokens="$(lesson_tokens "$query")"
        [ -n "$q_tokens" ] || exit 1
        matched=0
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          mistake="$(printf '%s' "$line" | jq -r '.mistake // ""' 2>/dev/null || echo "")"
          category="$(printf '%s' "$line" | jq -r '.category // ""' 2>/dev/null || echo "")"
          correction="$(printf '%s' "$line" | jq -r '.correction // ""' 2>/dev/null || echo "")"
          entry_tokens="$(lesson_tokens "$mistake $category")"
          overlap=0
          for t in $q_tokens; do
            case " $entry_tokens " in
              *" $t "*) overlap=$((overlap+1)) ;;
            esac
          done
          if [ "$overlap" -ge 2 ]; then
            printf '%s\n' "$correction"
            matched=1
          fi
        done < "$LESSONS_FILE"
        [ "$matched" -eq 1 ] && exit 0 || exit 1
        ;;
      *)
        echo "usage: $0 lesson {record --category <cat> --mistake \"<t>\" --correction \"<t>\" [--source <path>] | check \"<text>\"}"
        exit 1
        ;;
    esac
    ;;
  models)
    # shellcheck source=lib/models.sh
    . "$SCRIPT_DIR/lib/models.sh"
    shift
    cmd_models "$@"
    ;;
  trace)
    # shellcheck source=lib/trace.sh
    . "$SCRIPT_DIR/lib/trace.sh"
    shift
    cmd_trace "$@"
    ;;
  mem)
    # shellcheck source=lib/mem.sh
    . "$SCRIPT_DIR/lib/mem.sh"
    shift
    cmd_mem "$@"
    ;;
  session)
    # shellcheck source=lib/session.sh
    . "$SCRIPT_DIR/lib/session.sh"
    shift
    cmd_session "$@"
    ;;
  engine)
    # shellcheck source=lib/engine.sh
    . "$SCRIPT_DIR/lib/engine.sh"
    shift
    cmd_engine "$@"
    ;;
  scope-check)
    worktree_path="${2:-}"
    base_ref="${3:-}"
    allowed_csv="${4:-}"
    [ -n "$worktree_path" ] && [ -n "$base_ref" ] && [ -n "$allowed_csv" ] || { echo "usage: $0 scope-check <worktree-path> <base-ref> <allowed-file-list>" >&2; exit 1; }
    allowed_set="|$allowed_csv|"
    merge_base="$(git -C "$worktree_path" merge-base "$base_ref" HEAD)"
    offending=""
    while IFS= read -r changed; do
      [ -n "$changed" ] || continue
      case "$allowed_set" in *"|$changed|"*) ;; *) offending="$offending$changed\n" ;; esac
    done < <({ git -C "$worktree_path" diff --name-only "$merge_base"; git -C "$worktree_path" ls-files --others --exclude-standard; } | sort -u)
    if [ -n "$offending" ]; then
      printf '%b' "$offending"
      exit 1
    fi
    exit 0
    ;;
  worktree)
    subcmd="${2:-}"
    shift 2
    case "$subcmd" in
      check)
        path="${1:-.}"
        cd "$path" || exit 1

        # Resolve repo root for the current working tree
        wt_root="$(git rev-parse --show-toplevel)"
        # Resolve the shared .git dir (works from both main and linked worktree)
        git_common="$(cd "$(git rev-parse --git-common-dir)" && pwd)"

        # Determine effective hooks directory
        hooks_path_cfg="$(git config --get core.hooksPath 2>/dev/null || true)"
        if [ -n "$hooks_path_cfg" ]; then
          case "$hooks_path_cfg" in
            /*) hookdir="$hooks_path_cfg" ;;
            *)  hookdir="$wt_root/$hooks_path_cfg" ;;
          esac
        else
          hookdir="$git_common/hooks"
        fi

        # HARDCODED_HOOK_PATH: any executable hook (non-sample) containing /Users/ or /home/
        if [ -d "$hookdir" ]; then
          for _hf in "$hookdir"/*; do
            [ -f "$_hf" ] || continue
            case "$_hf" in *.sample) continue ;; esac
            if grep -qE '/Users/|/home/' "$_hf" 2>/dev/null; then
              echo "HARDCODED_HOOK_PATH"
              break
            fi
          done
        fi

        # HOOKS_PATH_ABSOLUTE: core.hooksPath set to an absolute path
        if [ -n "$hooks_path_cfg" ]; then
          case "$hooks_path_cfg" in
            /*) echo "HOOKS_PATH_ABSOLUTE" ;;
          esac
        fi

        # MISSING_ENV_FILE: gitignored .env* present on disk
        _found_env=0
        for _ef in .env .env.*; do
          [ -f "$_ef" ] || continue
          if git check-ignore -q "$_ef" 2>/dev/null; then
            echo "MISSING_ENV_FILE"
            _found_env=1
            break
          fi
        done

        # MISSING_BOOTSTRAP_ARTIFACT: gitignored build/dep dir present
        for _art in node_modules .terraform env venv .venv; do
          if [ -d "$_art" ] && git check-ignore -q "$_art" 2>/dev/null; then
            echo "MISSING_BOOTSTRAP_ARTIFACT"
            break
          fi
        done
        ;;
      provision)
        branch=""
        force=0
        pr_mode=0
        while [ $# -gt 0 ]; do
          case "$1" in
            --force) force=1; shift ;;
            --pr) pr_mode=1; shift ;;
            *) branch="$1"; shift ;;
          esac
        done

        [ -n "$branch" ] || { echo "usage: worktree provision <branch> [--force] [--pr]"; exit 1; }

        # Check for hazards
        hazards=$("$0" worktree check)

        if [ -n "$hazards" ] && [ $force -eq 0 ] && [ $pr_mode -eq 0 ]; then
          echo "Hazards detected (use --force to override):"
          echo "$hazards"
          exit 1
        fi

        # Print hazards if forcing
        if [ -n "$hazards" ] && [ $force -eq 1 ]; then
          echo "$hazards"
        fi

        # Create worktree
        wt_dir=".claude/worktrees/$branch"
        mkdir -p .claude/worktrees
        git worktree add "$wt_dir" -b "$branch" 2>/dev/null || git worktree add "$wt_dir" "$branch"

        if [ $pr_mode -eq 1 ]; then
          # Ensure .loops exists for logging
          mkdir -p "$LOOPDIR"
          [ -f "$LOOPDIR/log.md" ] || echo "# Loop log" > "$LOOPDIR/log.md"

          # Save absolute path to the fixture/original repo (where we log back to)
          main_repo="$(pwd)"

          # Move to worktree and apply fixes (use SCRIPT_DIR — the loops tool's
          # own location — never a path relative to the repo being provisioned)
          cd "$wt_dir"
          bash "$SCRIPT_DIR/run.sh" worktree fix --force

          # fix() writes remediated hooks into the tracked .githooks/ directory.
          # Stage ONLY those specific paths, explicitly, one at a time.
          if [ -d ".githooks" ]; then
            for _hf in .githooks/*; do
              [ -f "$_hf" ] || continue
              git add "$_hf"
            done
          fi

          # Commit with hazard list in body
          body="Remediate worktree hazards:"
          for _tok in $hazards; do
            body="$body
- $_tok"
          done

          git commit -m "$body" 2>/dev/null || true

          # Create PR
          pr_url=$(gh pr create --draft --body "$body" 2>&1 | grep -o 'https://[^ ]*' | head -1)

          # Return to main repo and log
          cd "$main_repo"
          if [ -n "$pr_url" ]; then
            bash "$SCRIPT_DIR/run.sh" log "worktree" "opened PR $pr_url"
          fi
        fi
        ;;
      fix)
        force=0
        while [ $# -gt 0 ]; do
          case "$1" in
            --force) force=1; shift ;;
            *) shift ;;
          esac
        done

        # Check for dirty tree (unless forcing)
        if [ $force -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
          echo "Dirty tree (use --force to override)"
          exit 1
        fi

        # Resolve the MAIN repo root regardless of which worktree `fix` runs
        # from. `--show-toplevel` resolves to whichever worktree is current
        # (provision --pr invokes fix from inside the linked worktree), so we
        # must derive it the same way the emitted hook does: via
        # git-common-dir, which always points at the main repo's .git. This
        # is the value hardcoded hook paths are expected to be prefixed
        # with — hooks are shared across worktrees but the absolute paths
        # baked into them (e.g. a venv) point at the MAIN checkout.
        git_common="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
        main_root="$(dirname "$git_common")"

        # The DESTINATION for the tracked .githooks/ copy is different: it
        # must be the CURRENT working tree (so the commit provision --pr
        # makes actually contains it), which is the linked worktree when
        # invoked from there.
        cwd_root="$(git rev-parse --show-toplevel)"

        # Fix HARDCODED_HOOK_PATH
        # Remediation: copy hooks to .githooks/ (tracked, committable) with absolute paths
        # rewritten to derive from the main worktree via git-common-dir. Set core.hooksPath
        # to ".githooks" (relative) so the tracked copy is used instead of .git/hooks.
        hookdir="$git_common/hooks"
        if [ -d "$hookdir" ]; then
          _any_hook=0
          for _hf in "$hookdir"/*; do
            [ -f "$_hf" ] || continue
            case "$_hf" in *.sample) continue ;; esac

            if grep -qE '/Users/|/home/' "$_hf" 2>/dev/null; then
              # Create tracked .githooks/ directory in the CURRENT working tree
              mkdir -p "$cwd_root/.githooks"
              _name=$(basename "$_hf")
              _dest="$cwd_root/.githooks/$_name"

              # Rewrite absolute paths, prepending MAIN_WT derivation.
              # `repo` here is the MAIN repo root — the hardcoded paths must
              # match it as a literal prefix, not the current worktree.
              _tmp=$(mktemp)
              awk -v repo="$main_root" '
              BEGIN { injected=0 }
              /\/(Users|home)\// && !injected {
                print "# Derive main worktree path dynamically"
                print "MAIN_WT=$(dirname \"$(cd \"$(git rev-parse --git-common-dir)\" && pwd)\")"
                injected=1
              }
              {
                line = $0
                while (match(line, /\/(Users|home)\/[^"$'"'"' \t)]+/)) {
                  before = substr(line, 1, RSTART-1)
                  matched = substr(line, RSTART, RLENGTH)
                  after = substr(line, RSTART+RLENGTH)
                  if (index(matched, repo) == 1) {
                    suffix = substr(matched, length(repo)+1)
                    line = before "$MAIN_WT" suffix after
                  } else {
                    # Path does not start with repo root — cannot safely rewrite.
                    # Fail loudly rather than guessing.
                    print "ERROR: Cannot rewrite path outside repo root: " matched > "/dev/stderr"
                    print "       in hook: " FILENAME > "/dev/stderr"
                    exit 1
                  }
                }
                print line
              }
              ' "$_hf" > "$_tmp"
              if [ $? -ne 0 ]; then
                rm -f "$_tmp"
                exit 1
              fi
              mv "$_tmp" "$_dest"
              chmod +x "$_dest"
              _any_hook=1
            fi
          done

          if [ "$_any_hook" -eq 1 ]; then
            # Set core.hooksPath to relative .githooks (fixes HOOKS_PATH_ABSOLUTE too)
            git config core.hooksPath .githooks
          fi
        fi

        # Fix HOOKS_PATH_ABSOLUTE (if not already fixed by the HARDCODED fix above)
        hooks_path_cfg="$(git config --get core.hooksPath 2>/dev/null || true)"
        if [ -n "$hooks_path_cfg" ]; then
          case "$hooks_path_cfg" in
            /*) git config --unset core.hooksPath ;;
          esac
        fi
        ;;
      reap)
        path="."
        prune=0
        while [ $# -gt 0 ]; do
          case "$1" in
            --prune) prune=1; shift ;;
            *) path="$1"; shift ;;
          esac
        done

        cd "$path" || exit 1

        # Parse git worktree list --porcelain to find orphans (directories deleted but git still tracks them)
        orphaned_wts=""
        current_wt=""
        while IFS= read -r line; do
          case "$line" in
            worktree\ *)
              current_wt="${line#worktree }"
              ;;
            "")
              if [ -n "$current_wt" ] && [ ! -d "$current_wt" ]; then
                echo "$current_wt"
                orphaned_wts="yes"
              fi
              current_wt=""
              ;;
          esac
        done < <(git worktree list --porcelain 2>/dev/null && echo "")

        if [ "$prune" -eq 1 ] && [ -n "$orphaned_wts" ]; then
          git worktree prune
        fi
        ;;
      *)
        echo "usage: $0 worktree {check [path] | provision <branch> [--force] [--pr] | fix [--force] | reap [path] [--prune]}"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "usage: $0 {[no args: interactive config] | init [\"goal\"] | status | score {record|stall} | reap | lint [path] | log \"<op>\" \"<title>\" | multireport <repo-path>... | lesson {record|check} | models {list|available|set} | trace {start|emit|end|validate} | session {show|set} | mem {show|note|fact|path|reap} | engine {show|set|run} | scope-check <wt> <base> <files> | worktree {check|provision|fix|reap}}"
    exit 1
    ;;
esac
