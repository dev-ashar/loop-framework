#!/usr/bin/env bash
# Test suite for LOOPS contract acceptance criteria
# One test function per criterion 2..38, printed in ascending order
# macOS/BSD userland; bash set -uo pipefail (NOT -e)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOOPS_RUN="$LOOPS_ROOT/run.sh"

# Track results (criteria 2..38 only, 37 total)
TOTAL=37
PASS_COUNT=0
FAIL_COUNT=0

# Global temp dir, cleaned up on exit
SUITE_TMPDIR=""

# Some fixtures (HARDCODED_HOOK_PATH rewrite tests) must live under a path
# that literally starts with /Users/ or /home/ — the hazard prefilter never
# matches the OS temp dir (/var/folders/... on macOS). Confine those to
# ~/.cache/loops-test.* (never scattered loose in $HOME) and track them via
# a registry file (not a shell array — fresh_home_tmp() is invoked as
# d=$(fresh_home_tmp), which runs in a command-substitution subshell, so an
# array mutation there would never reach the parent shell) so cleanup()
# removes them even if the suite is interrupted mid-run.
HOME_TMPDIR_REGISTRY=""

# Guard so cleanup() only ever does its work once: bash signal traps do NOT
# terminate the script on INT/TERM (execution resumes after the handler
# returns unless it exits explicitly), so on_signal() below calls cleanup()
# and then exits immediately. The EXIT trap still fires afterward (trapping
# EXIT always fires on process exit, including exit calls from other traps),
# so without this guard that second cleanup() run would rm -rf an
# already-removed SUITE_TMPDIR — harmless by itself, but confirms cleanup
# only runs once as designed.
CLEANUP_DONE=""

cleanup() {
  [ -n "$CLEANUP_DONE" ] && return 0
  CLEANUP_DONE=1
  # Read the registry before removing SUITE_TMPDIR (the registry file lives
  # inside it), so interrupted/early runs still see every recorded path.
  if [ -n "$HOME_TMPDIR_REGISTRY" ] && [ -f "$HOME_TMPDIR_REGISTRY" ]; then
    local hd
    while IFS= read -r hd; do
      [ -n "$hd" ] && [ -d "$hd" ] && rm -rf "$hd"
    done < "$HOME_TMPDIR_REGISTRY"
  fi
  [ -n "$SUITE_TMPDIR" ] && [ -d "$SUITE_TMPDIR" ] && rm -rf "$SUITE_TMPDIR"
}

# INT/TERM traps run a handler but do NOT terminate the script afterward —
# execution would otherwise fall through and keep running against a
# SUITE_TMPDIR that cleanup() just deleted (the exact bug this fixes: fixtures
# created after the signal landed under a removed directory, so registry
# appends silently failed and were never cleaned up). Exit explicitly with
# the conventional 128+signum code so the process actually terminates.
on_signal() {
  cleanup
  exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap cleanup EXIT

# Allocate a fresh scratch directory
fresh_tmp() {
  local d
  d=$(mktemp -d "$SUITE_TMPDIR/testXXXXXX")
  echo "$d"
}

# Allocate a fresh scratch directory rooted under $HOME (so its path matches
# the /Users/|/home/ hazard prefilter), confined to ~/.cache and cleaned up
# by the trap above even on interruption.
fresh_home_tmp() {
  local d
  mkdir -p "$HOME/.cache"
  d=$(mktemp -d "$HOME/.cache/loops-test.XXXXXX")
  # Called as d=$(fresh_home_tmp) — a command-substitution subshell — so
  # record the path in the registry FILE, not a shell array/variable: any
  # variable mutation here is invisible to the parent shell.
  echo "$d" >> "$HOME_TMPDIR_REGISTRY"
  echo "$d"
}

# Record test result. Criterion 1 is the suite's own meta-check: printed in
# sequence but NOT counted in the 37-denominator tally (which covers only
# criteria 2..38 per the contract's "37/37 passed" literal).
record_result() {
  local n="$1"
  local status="$2"
  local message="$3"

  echo "[$status] criterion $n: $message"

  if [ "$n" = "1" ]; then
    return
  fi

  if [ "$status" = "pass" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Anti-negation guard: checks ±2 lines around every line in FILE that matches
# PATTERN (ERE) for negation tokens. Returns 0 if no negation found, 1 if found.
check_anti_negation_guard() {
  local file="$1"
  local pattern="$2"

  local line_count
  line_count=$(wc -l < "$file")

  local matches
  matches=$(grep -nE "$pattern" "$file" | cut -d: -f1)
  [ -z "$matches" ] && return 1  # pattern not found at all

  local negation_regex='not[[:space:]]|never[[:space:]]|avoid[[:space:]]|don'"'"'t[[:space:]]|do not[[:space:]]|optional[[:space:]]|skip[[:space:]]'

  for linenum in $matches; do
    local start=$((linenum - 2))
    [ $start -lt 1 ] && start=1
    local end=$((linenum + 2))
    [ $end -gt "$line_count" ] && end=$line_count

    # Extract ±2 line window and check for negation tokens (case-insensitive)
    if sed -n "${start},${end}p" "$file" | grep -Eiq "$negation_regex"; then
      return 1  # Guard failed: negation found
    fi
  done

  return 0  # Guard passed
}

# ============================================================================
# Phase 0 — suite meta-check (criterion 1)
# ============================================================================

test_criterion_1() {
  local missing=""
  for n in $(seq 2 38); do
    if ! declare -f "test_criterion_$n" >/dev/null 2>&1; then
      missing="$missing $n"
    fi
  done

  if [ -n "$missing" ]; then
    record_result 1 "FAIL" "missing test functions:$missing"
  else
    record_result 1 "pass" "all 37 test functions defined and invoked in order"
  fi
}

# ============================================================================
# Phase 1 — foundations (criteria 2–15)
# ============================================================================

test_criterion_2() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  "$LOOPS_RUN" init >/dev/null 2>&1

  local history
  history=$(jq '.metric.history' .loops/feature_list.json)

  cd - >/dev/null
  if [ "$history" = "[]" ]; then
    record_result 2 "pass" "feature_list.json has empty metric.history array"
  else
    record_result 2 "FAIL" "metric.history is not []: got $history"
  fi
}

test_criterion_3() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  "$LOOPS_RUN" init >/dev/null 2>&1

  "$LOOPS_RUN" score record 1 0.5 "BLOCK" >/dev/null 2>&1
  "$LOOPS_RUN" score record 2 0.8 "PASS" >/dev/null 2>&1

  local len iter1 score1 verdict1 ts1
  len=$(jq '.metric.history | length' .loops/feature_list.json)
  iter1=$(jq '.metric.history[0].iteration' .loops/feature_list.json)
  score1=$(jq '.metric.history[0].score' .loops/feature_list.json)
  verdict1=$(jq -r '.metric.history[0].verdict' .loops/feature_list.json)
  ts1=$(jq -r '.metric.history[0].ts' .loops/feature_list.json)

  cd - >/dev/null

  if [ "$len" = "2" ] && [ "$iter1" = "1" ] && [ "$score1" = "0.5" ] && \
     [ "$verdict1" = "BLOCK" ] && [ -n "$ts1" ] && [ "$ts1" != "null" ]; then
    record_result 3 "pass" "score record appends all four keys correctly"
  else
    record_result 3 "FAIL" "score record: len=$len iter=$iter1 score=$score1 verdict=$verdict1 ts=$ts1"
  fi
}

test_criterion_4() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  "$LOOPS_RUN" init >/dev/null 2>&1

  # [0.5, 0.5] → exit 2
  "$LOOPS_RUN" score record 1 0.5 "BLOCK" >/dev/null 2>&1
  "$LOOPS_RUN" score record 2 0.5 "BLOCK" >/dev/null 2>&1
  "$LOOPS_RUN" score stall >/dev/null 2>&1
  local exit1=$?

  # Reset
  jq '.metric.history = []' .loops/feature_list.json > /tmp/loops_test_fl.json
  mv /tmp/loops_test_fl.json .loops/feature_list.json

  # [0.5, 0.4] → exit 2
  "$LOOPS_RUN" score record 1 0.5 "BLOCK" >/dev/null 2>&1
  "$LOOPS_RUN" score record 2 0.4 "BLOCK" >/dev/null 2>&1
  "$LOOPS_RUN" score stall >/dev/null 2>&1
  local exit2=$?

  # Reset
  jq '.metric.history = []' .loops/feature_list.json > /tmp/loops_test_fl.json
  mv /tmp/loops_test_fl.json .loops/feature_list.json

  # [0.5, 0.8] → exit 0
  "$LOOPS_RUN" score record 1 0.5 "BLOCK" >/dev/null 2>&1
  "$LOOPS_RUN" score record 2 0.8 "PASS" >/dev/null 2>&1
  "$LOOPS_RUN" score stall >/dev/null 2>&1
  local exit3=$?

  cd - >/dev/null

  if [ $exit1 -eq 2 ] && [ $exit2 -eq 2 ] && [ $exit3 -eq 0 ]; then
    record_result 4 "pass" "stall correctly detects non-increasing scores"
  else
    record_result 4 "FAIL" "stall exit codes wrong: equal=$exit1 decreasing=$exit2 increasing=$exit3"
  fi
}

test_criterion_5() {
  local skill_file="$LOOPS_ROOT/.claude/skills/run-loop/SKILL.md"

  # Extract step 2's span: from "### 2. Build" through the line before the next "###" heading
  # BSD-safe: use awk, exclude the boundary lines
  local step2_file
  step2_file=$(fresh_tmp)/step2.txt
  awk '/^### 2\. Build/, /^### [^2]/{if (/^### [^2]/) next; print}' "$skill_file" > "$step2_file"

  if ! grep -q 'run\.sh score record' "$step2_file"; then
    record_result 5 "FAIL" "run.sh score record not found in step 2"
    return
  fi

  if ! grep -q 'run\.sh score stall' "$step2_file"; then
    record_result 5 "FAIL" "run.sh score stall not found in step 2"
    return
  fi

  if ! check_anti_negation_guard "$step2_file" 'run\.sh score record'; then
    record_result 5 "FAIL" "score record has negation in its ±2 line window"
    return
  fi

  if ! check_anti_negation_guard "$step2_file" 'run\.sh score stall'; then
    record_result 5 "FAIL" "score stall has negation in its ±2 line window"
    return
  fi

  record_result 5 "pass" "step 2 contains score record/stall with no negation"
}

test_criterion_6() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  "$LOOPS_RUN" init >/dev/null 2>&1

  touch .loops/.running
  local bdtime
  bdtime=$(date -v-50H +%Y%m%d%H%M)
  touch -t "$bdtime" .loops/.running

  jq '.metric.history += [{"iteration":1,"score":1.0,"verdict":"PASS","ts":"2026-01-01T00:00:00Z"}]' \
    .loops/feature_list.json > /tmp/loops_test_fl.json
  mv /tmp/loops_test_fl.json .loops/feature_list.json

  local sha_before
  sha_before=$(shasum -a 256 .loops/.running | cut -d' ' -f1)

  local output exit_code
  output=$("$LOOPS_RUN" reap 2>&1)
  exit_code=$?

  local sha_after
  sha_after=$(shasum -a 256 .loops/.running | cut -d' ' -f1)

  cd - >/dev/null

  if echo "$output" | grep -q "AWAITING LANDING APPROVAL" && \
     [ $exit_code -eq 0 ] && [ "$sha_before" = "$sha_after" ]; then
    record_result 6 "pass" "reap reports AWAITING with PASS verdict, read-only"
  else
    record_result 6 "FAIL" "output='$output' exit=$exit_code sha_unchanged=$([ "$sha_before" = "$sha_after" ] && echo y || echo n)"
  fi
}

test_criterion_7() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  "$LOOPS_RUN" init >/dev/null 2>&1

  touch .loops/.running
  local bdtime
  bdtime=$(date -v-50H +%Y%m%d%H%M)
  touch -t "$bdtime" .loops/.running

  jq '.metric.history += [{"iteration":1,"score":0.5,"verdict":"BLOCK","ts":"2026-01-01T00:00:00Z"}]' \
    .loops/feature_list.json > /tmp/loops_test_fl.json
  mv /tmp/loops_test_fl.json .loops/feature_list.json

  local sha_before
  sha_before=$(shasum -a 256 .loops/.running | cut -d' ' -f1)

  local output exit_code
  output=$("$LOOPS_RUN" reap 2>&1)
  exit_code=$?

  local sha_after
  sha_after=$(shasum -a 256 .loops/.running | cut -d' ' -f1)

  cd - >/dev/null

  if echo "$output" | grep -q "STALE" && \
     [ $exit_code -eq 1 ] && [ "$sha_before" = "$sha_after" ]; then
    record_result 7 "pass" "reap reports STALE with BLOCK verdict, read-only"
  else
    record_result 7 "FAIL" "output='$output' exit=$exit_code sha_unchanged=$([ "$sha_before" = "$sha_after" ] && echo y || echo n)"
  fi
}

test_criterion_8() {
  local d
  d=$(fresh_tmp)
  cd "$d"

  local bdtime
  bdtime=$(date -v-50H +%Y%m%d%H%M)

  # --- Mode 1: AWAITING ---
  "$LOOPS_RUN" init >/dev/null 2>&1
  touch .loops/.running .loops/sentinel1 .loops/sentinel2
  touch -t "$bdtime" .loops/.running
  jq '.metric.history += [{"iteration":1,"score":1.0,"verdict":"PASS","ts":"2026-01-01T00:00:00Z"}]' \
    .loops/feature_list.json > /tmp/loops_test_fl.json && mv /tmp/loops_test_fl.json .loops/feature_list.json

  local ls_before sha_before mtime_before inode_before
  ls_before=$(ls -a .loops/ | sort | tr '\n' '|')
  sha_before=$(shasum -a 256 .loops/.running | cut -d' ' -f1)
  mtime_before=$(stat -f %m .loops/.running)
  inode_before=$(stat -f %i .loops/.running)

  "$LOOPS_RUN" reap >/dev/null 2>&1

  local ls_after sha_after mtime_after inode_after running_sibling
  ls_after=$(ls -a .loops/ | sort | tr '\n' '|')
  sha_after=$(shasum -a 256 .loops/.running | cut -d' ' -f1)
  mtime_after=$(stat -f %m .loops/.running)
  inode_after=$(stat -f %i .loops/.running)
  running_sibling=$(ls -a .loops/ | grep -cE '^\.running\.' || true)

  if [ "$ls_before" != "$ls_after" ] || [ "$sha_before" != "$sha_after" ] || \
     [ "$mtime_before" != "$mtime_after" ] || [ "$inode_before" != "$inode_after" ] || \
     [ "$running_sibling" -gt 0 ]; then
    record_result 8 "FAIL" "reap AWAITING mode mutated .loops/"
    cd - >/dev/null
    return
  fi

  # --- Mode 2: STALE ---
  rm -rf .loops
  "$LOOPS_RUN" init >/dev/null 2>&1
  touch .loops/.running .loops/sentinel1 .loops/sentinel2
  touch -t "$bdtime" .loops/.running
  jq '.metric.history += [{"iteration":1,"score":0.5,"verdict":"BLOCK","ts":"2026-01-01T00:00:00Z"}]' \
    .loops/feature_list.json > /tmp/loops_test_fl.json && mv /tmp/loops_test_fl.json .loops/feature_list.json

  ls_before=$(ls -a .loops/ | sort | tr '\n' '|')
  sha_before=$(shasum -a 256 .loops/.running | cut -d' ' -f1)
  mtime_before=$(stat -f %m .loops/.running)
  inode_before=$(stat -f %i .loops/.running)

  "$LOOPS_RUN" reap >/dev/null 2>&1 || true

  ls_after=$(ls -a .loops/ | sort | tr '\n' '|')
  sha_after=$(shasum -a 256 .loops/.running | cut -d' ' -f1)
  mtime_after=$(stat -f %m .loops/.running)
  inode_after=$(stat -f %i .loops/.running)
  running_sibling=$(ls -a .loops/ | grep -cE '^\.running\.' || true)

  if [ "$ls_before" != "$ls_after" ] || [ "$sha_before" != "$sha_after" ] || \
     [ "$mtime_before" != "$mtime_after" ] || [ "$inode_before" != "$inode_after" ] || \
     [ "$running_sibling" -gt 0 ]; then
    record_result 8 "FAIL" "reap STALE mode mutated .loops/"
    cd - >/dev/null
    return
  fi

  # --- Mode 3: no .running ---
  rm -rf .loops
  "$LOOPS_RUN" init >/dev/null 2>&1
  touch .loops/sentinel1 .loops/sentinel2

  ls_before=$(ls -a .loops/ | sort | tr '\n' '|')

  "$LOOPS_RUN" reap >/dev/null 2>&1

  ls_after=$(ls -a .loops/ | sort | tr '\n' '|')

  if [ "$ls_before" != "$ls_after" ]; then
    record_result 8 "FAIL" "reap no-.running mode mutated .loops/"
    cd - >/dev/null
    return
  fi

  cd - >/dev/null
  record_result 8 "pass" "reap is read-only in all three modes"
}

test_criterion_9() {
  local d
  d=$(fresh_tmp)

  # Fixture (a): fully valid contract
  cat > "$d/valid.md" <<'EOF'
# Contract

## Goal
Build something.

## Constraints
- Keep it simple.

## Acceptance criteria

### Phase 1
- [ ] 1. First criterion.
- [ ] 2. Second criterion with continuation
  that is indented by 2 spaces.

> A blockquote is allowed.

## Verify command

```bash
echo "test"
```
EOF

  "$LOOPS_RUN" lint "$d/valid.md" >/dev/null 2>&1
  local exit_a=$?

  # Fixture (b): bare prose paragraph in criteria section
  cat > "$d/prose.md" <<'EOF'
# Contract

## Goal
Build something.

## Constraints
- Keep it simple.

## Acceptance criteria
- [ ] 1. First criterion.

This is bare prose that violates the format.

## Verify command

```bash
echo "test"
```
EOF

  local output_b
  output_b=$("$LOOPS_RUN" lint "$d/prose.md" 2>&1)
  local exit_b=$?

  # Fixture (c): missing ## Verify heading
  cat > "$d/no_verify.md" <<'EOF'
# Contract

## Goal
Build something.

## Constraints
- Keep it simple.

## Acceptance criteria
- [ ] 1. First criterion.
EOF

  local output_c
  output_c=$("$LOOPS_RUN" lint "$d/no_verify.md" 2>&1)
  local exit_c=$?

  # Fixture (d1): missing ## Goal
  cat > "$d/no_goal.md" <<'EOF'
# Contract

## Constraints
- Keep it simple.

## Acceptance criteria
- [ ] 1. First criterion.

## Verify command

```bash
echo "test"
```
EOF

  local output_d1
  output_d1=$("$LOOPS_RUN" lint "$d/no_goal.md" 2>&1)
  local exit_d1=$?

  # Fixture (d2): missing ## Constraints
  cat > "$d/no_constraints.md" <<'EOF'
# Contract

## Goal
Build something.

## Acceptance criteria
- [ ] 1. First criterion.

## Verify command

```bash
echo "test"
```
EOF

  local output_d2
  output_d2=$("$LOOPS_RUN" lint "$d/no_constraints.md" 2>&1)
  local exit_d2=$?

  # Fixture (e): ## Verify present but NO fenced code block
  cat > "$d/no_fence.md" <<'EOF'
# Contract

## Goal
Build something.

## Constraints
- Keep it simple.

## Acceptance criteria
- [ ] 1. First criterion.

## Verify command

Just plain text, no fence here.
EOF

  local output_e
  output_e=$("$LOOPS_RUN" lint "$d/no_fence.md" 2>&1)
  local exit_e=$?

  local fail=""
  [ $exit_a -ne 0 ]                        && fail="$fail (a)valid→non-zero"
  [ $exit_b -eq 0 ]                        && fail="$fail (b)prose→zero"
  ! echo "$output_b" | grep -q "line"      && fail="$fail (b)no-line-num"
  [ $exit_c -eq 0 ]                        && fail="$fail (c)no-verify→zero"
  ! echo "$output_c" | grep -iq "verify"   && fail="$fail (c)no-verify-msg"
  [ $exit_d1 -eq 0 ]                       && fail="$fail (d1)no-goal→zero"
  ! echo "$output_d1" | grep -iq "goal"    && fail="$fail (d1)no-goal-msg"
  [ $exit_d2 -eq 0 ]                       && fail="$fail (d2)no-constraints→zero"
  ! echo "$output_d2" | grep -iq "constraints" && fail="$fail (d2)no-constraints-msg"
  [ $exit_e -eq 0 ]                        && fail="$fail (e)no-fence→zero"
  ! echo "$output_e" | grep -Eiq "fenced|fence|code block|\`\`\`" && fail="$fail (e)no-fence-msg"

  if [ -z "$fail" ]; then
    record_result 9 "pass" "lint validates all five contract structure checks"
  else
    record_result 9 "FAIL" "lint sub-checks failed:$fail"
  fi
}

test_criterion_10() {
  "$LOOPS_RUN" lint "$LOOPS_ROOT/.loops/contract.md" >/dev/null 2>&1
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    record_result 10 "pass" "lint accepts the real contract file"
  else
    record_result 10 "FAIL" "lint rejects the real contract (exit $exit_code)"
  fi
}

test_criterion_11() {
  local skill_file="$LOOPS_ROOT/.claude/skills/contract/SKILL.md"

  # Extract Lock step (step 6) through the next numbered step or section end
  local lock_file
  lock_file=$(fresh_tmp)/lock_step.txt
  awk '/^6\. \*\*Lock/, /^[0-9]+\. |^## /{
    if (/^[0-9]+\. / && !/^6\./ ) next
    if (/^## /) next
    print
  }' "$skill_file" > "$lock_file"

  if ! grep -q 'run\.sh lint' "$lock_file"; then
    record_result 11 "FAIL" "run.sh lint not found in Lock step"
    return
  fi

  if ! check_anti_negation_guard "$lock_file" 'run\.sh lint'; then
    record_result 11 "FAIL" "run.sh lint has negation in its ±2 line window"
    return
  fi

  record_result 11 "pass" "Lock step contains run.sh lint with no negation"
}

test_criterion_12() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  "$LOOPS_RUN" init >/dev/null 2>&1

  "$LOOPS_RUN" log "build" "implemented feature X" >/dev/null 2>&1

  local last_line
  last_line=$(tail -n 1 .loops/log.md)
  cd - >/dev/null

  if echo "$last_line" | grep -Eq '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] .+ \| .+$'; then
    record_result 12 "pass" "log appends well-formed line"
  else
    record_result 12 "FAIL" "log line malformed: $last_line"
  fi
}

test_criterion_13() {
  local d
  d=$(fresh_tmp)

  # Fixture (a): time dropped — date without HH:MM (named log.md for lint to detect it)
  cat > "$d/log.md" <<'EOF'
## [2026-07-25] act | dedup fix applied
EOF

  local output_a exit_a
  output_a=$("$LOOPS_RUN" lint "$d/log.md" 2>&1)
  exit_a=$?
  rm -f "$d/log.md"

  # Fixture (b): missing " | " separator
  cat > "$d/log.md" <<'EOF'
## [2026-07-25 20:35] act dedup fix applied
EOF

  local output_b exit_b
  output_b=$("$LOOPS_RUN" lint "$d/log.md" 2>&1)
  exit_b=$?
  rm -f "$d/log.md"

  # Fixture (c): unparseable date component
  cat > "$d/log.md" <<'EOF'
## [not-a-date 20:35] act | x
EOF

  local output_c exit_c
  output_c=$("$LOOPS_RUN" lint "$d/log.md" 2>&1)
  exit_c=$?
  rm -f "$d/log.md"

  # Fixture (d): well-formed — must exit 0
  cat > "$d/log.md" <<'EOF'
## [2026-07-25 20:35] act | dedup fix applied
EOF

  "$LOOPS_RUN" lint "$d/log.md" >/dev/null 2>&1
  local exit_d=$?

  local fail=""
  [ $exit_a -eq 0 ] && fail="$fail (a)no-time-→-zero"
  [ $exit_b -eq 0 ] && fail="$fail (b)no-sep-→-zero"
  [ $exit_c -eq 0 ] && fail="$fail (c)bad-date-→-zero"
  [ $exit_d -ne 0 ] && fail="$fail (d)well-formed-→-nonzero"

  if [ -z "$fail" ]; then
    record_result 13 "pass" "lint validates all four log format fixtures"
  else
    record_result 13 "FAIL" "log lint failures:$fail"
  fi
}

test_criterion_14() {
  # Expected hashes hardcoded from contract — NOT recomputed from files
  local expected_pre="310499bb8919f84661131adbd243a124ad2329a0f73140a4f5c1380515e043cc"
  local expected_post="b8b65b36bddcbe700b48850f4feef7f8ddac2561e620c25d7de9ca67821e8e78"
  local expected_stop="3419ac17dce751736b0f33f2b9aa484776e26219b9f22a1a141c85d71093c77e"

  local actual_pre actual_post actual_stop hook_count
  actual_pre=$(shasum -a 256 "$LOOPS_ROOT/.claude/hooks/pre-tool-use.sh" 2>/dev/null | cut -d' ' -f1)
  actual_post=$(shasum -a 256 "$LOOPS_ROOT/.claude/hooks/post-tool-use.sh" 2>/dev/null | cut -d' ' -f1)
  actual_stop=$(shasum -a 256 "$LOOPS_ROOT/.claude/hooks/stop.sh" 2>/dev/null | cut -d' ' -f1)
  hook_count=$(ls -1 "$LOOPS_ROOT/.claude/hooks/" 2>/dev/null | wc -l | tr -d ' ')

  local fail=""
  [ "$actual_pre" != "$expected_pre" ]   && fail="$fail pre-tool-use.sh hash mismatch"
  [ "$actual_post" != "$expected_post" ] && fail="$fail post-tool-use.sh hash mismatch"
  [ "$actual_stop" != "$expected_stop" ] && fail="$fail stop.sh hash mismatch"
  [ "$hook_count" != "3" ]               && fail="$fail expected 3 hooks got $hook_count"

  if [ -z "$fail" ]; then
    record_result 14 "pass" "hooks unchanged, exactly three files"
  else
    record_result 14 "FAIL" "$fail"
  fi
}

test_criterion_15() {
  local d
  d=$(fresh_tmp)

  # ── Repo A: 2 worktrees, 3 dirty files, .running present, well-formed log ──
  local repo_a="$d/repo_a"
  mkdir -p "$repo_a"
  git -C "$repo_a" init -q
  git -C "$repo_a" config user.name "Test"
  git -C "$repo_a" config user.email "test@test.com"

  # Commit initial tracked files (including .loops/ skeleton so it's not untracked)
  mkdir -p "$repo_a/.loops"
  echo "placeholder" > "$repo_a/.loops/.gitkeep"
  echo "main" > "$repo_a/file.txt"
  git -C "$repo_a" add -A
  git -C "$repo_a" commit -q -m "initial"

  # Add second worktree
  git -C "$repo_a" worktree add -q "$d/repo_a_wt1" -b wt1

  # Create 3 tracked files, plus .running and log.md, and commit them all first
  # so only the 3 target files end up dirty (.running/.loops must NOT be untracked
  # noise, since dirty-file count must equal exactly 3).
  echo "tracked1" > "$repo_a/dirty1.txt"
  echo "tracked2" > "$repo_a/dirty2.txt"
  echo "tracked3" > "$repo_a/dirty3.txt"
  touch "$repo_a/.loops/.running"
  echo "## [2026-07-29 10:00] build | first entry" > "$repo_a/.loops/log.md"
  echo "## [2026-07-29 11:00] test | second entry" >> "$repo_a/.loops/log.md"
  git -C "$repo_a" add -A
  git -C "$repo_a" commit -q -m "add dirty files, running marker, log"

  # Now modify the 3 files so they show as dirty (modified) in status — nothing else
  echo "modified1" > "$repo_a/dirty1.txt"
  echo "modified2" > "$repo_a/dirty2.txt"
  echo "modified3" > "$repo_a/dirty3.txt"

  local wt_a_before
  wt_a_before=$(git -C "$repo_a" status --porcelain)

  # ── Repo B: 1 worktree, 0 dirty, no .running, log ≥1 entry, no contract ──
  local repo_b="$d/repo_b"
  mkdir -p "$repo_b"
  git -C "$repo_b" init -q
  git -C "$repo_b" config user.name "Test"
  git -C "$repo_b" config user.email "test@test.com"

  mkdir -p "$repo_b/.loops"
  echo "placeholder" > "$repo_b/.loops/.gitkeep"
  echo "main" > "$repo_b/file.txt"
  git -C "$repo_b" add -A
  git -C "$repo_b" commit -q -m "initial"

  # Commit log.md into repo_b so it's not untracked
  echo "## [2026-07-29 12:00] build | something happened" > "$repo_b/.loops/log.md"
  git -C "$repo_b" add "$repo_b/.loops/log.md"
  git -C "$repo_b" commit -q -m "add log"

  local wt_b_before
  wt_b_before=$(git -C "$repo_b" status --porcelain)

  # Run multireport
  local output exit_code
  output=$("$LOOPS_RUN" multireport "$repo_a" "$repo_b" 2>&1)
  exit_code=$?

  local wt_a_after wt_b_after
  wt_a_after=$(git -C "$repo_a" status --porcelain)
  wt_b_after=$(git -C "$repo_b" status --porcelain)

  # Parse repo A row
  local line_a line_b
  line_a=$(echo "$output" | grep "repo_a:")
  line_b=$(echo "$output" | grep "repo_b:")

  local a_wt a_dirty a_running a_log
  a_wt=$(echo "$line_a" | grep -o 'wt=[0-9]*' | cut -d= -f2)
  a_dirty=$(echo "$line_a" | grep -o 'dirty=[0-9]*' | cut -d= -f2)
  a_running=$(echo "$line_a" | grep -o 'running=[a-z]*' | cut -d= -f2)
  a_log=$(echo "$line_a" | grep -o 'log_ok=[a-z/]*' | cut -d= -f2)

  # Parse repo B row
  local b_wt b_dirty b_running b_log
  b_wt=$(echo "$line_b" | grep -o 'wt=[0-9]*' | cut -d= -f2)
  b_dirty=$(echo "$line_b" | grep -o 'dirty=[0-9]*' | cut -d= -f2)
  b_running=$(echo "$line_b" | grep -o 'running=[a-z]*' | cut -d= -f2)
  b_log=$(echo "$line_b" | grep -o 'log_ok=[a-z/]*' | cut -d= -f2)

  local warn_for_b no_warn_for_a
  warn_for_b=$(echo "$output" | grep -c "WARN: no contract.md" || true)
  # Check WARN not present for repo_a by verifying the WARN line doesn't mention repo_a
  no_warn_for_a=$(echo "$output" | grep "WARN" | grep -c "repo_a" || true)

  local fail=""
  [ "$a_wt" != "2" ]        && fail="$fail repo_a:wt=$a_wt(want 2)"
  [ "$a_dirty" != "3" ]     && fail="$fail repo_a:dirty=$a_dirty(want 3)"
  [ "$a_running" != "present" ] && fail="$fail repo_a:running=$a_running(want present)"
  [ "$a_log" != "y" ]       && fail="$fail repo_a:log_ok=$a_log(want y)"
  [ "$b_wt" != "1" ]        && fail="$fail repo_b:wt=$b_wt(want 1)"
  [ "$b_dirty" != "0" ]     && fail="$fail repo_b:dirty=$b_dirty(want 0)"
  [ "$b_running" != "absent" ] && fail="$fail repo_b:running=$b_running(want absent)"
  [ "$b_log" != "y" ]       && fail="$fail repo_b:log_ok=$b_log(want y)"
  [ "$warn_for_b" -lt 1 ]   && fail="$fail no-WARN-for-B"
  [ "$no_warn_for_a" -gt 0 ] && fail="$fail WARN-appeared-for-A"
  [ $exit_code -ne 0 ]      && fail="$fail exit=$exit_code(want 0)"
  [ "$wt_a_before" != "$wt_a_after" ] && fail="$fail repo_a-git-mutated"
  [ "$wt_b_before" != "$wt_b_after" ] && fail="$fail repo_b-git-mutated"

  if [ -z "$fail" ]; then
    record_result 15 "pass" "multireport correct values, warning on B only, read-only"
  else
    record_result 15 "FAIL" "$fail"
  fi
}

# ============================================================================
# Phase 2 — learning substrate (criteria 16–23)
# ============================================================================

# Amendment-specific helper for criterion 23: unlike check_anti_negation_guard
# (which fails if ANY match in the file is negated), this passes if AT LEAST
# ONE match of PATTERN in FILE survives the ±2-line guard. It reuses
# check_anti_negation_guard for the actual negation-window logic — it does not
# reimplement it — by running the guard against each match's own ±2 window in
# isolation and OR-ing the per-match results.
check_any_match_survives_guard() {
  local file="$1"
  local pattern="$2"

  local total_lines
  total_lines=$(wc -l < "$file")

  local matches
  matches=$(grep -nEi "$pattern" "$file" | cut -d: -f1)
  [ -z "$matches" ] && return 1

  local ln start end window_file
  window_file=$(fresh_tmp)/guard_window.txt
  for ln in $matches; do
    start=$((ln - 2))
    [ $start -lt 1 ] && start=1
    end=$((ln + 2))
    [ $end -gt "$total_lines" ] && end=$total_lines
    sed -n "${start},${end}p" "$file" > "$window_file"
    if check_anti_negation_guard "$window_file" "$pattern"; then
      return 0
    fi
  done

  return 1
}

test_criterion_16() {
  local d fake_home lessons_file
  d=$(fresh_tmp)
  fake_home="$d/home"
  mkdir -p "$fake_home"

  HOME="$fake_home" bash "$LOOPS_ROOT/install.sh" >/dev/null 2>&1
  lessons_file="$fake_home/.claude/memory/lessons.jsonl"

  if [ ! -f "$lessons_file" ]; then
    record_result 16 "FAIL" "lessons.jsonl not created on first install"
    return
  fi

  echo '{"category":"seed","mistake":"seed","correction":"seed","source":"","ts":"2026-01-01T00:00:00Z"}' >> "$lessons_file"
  local count_before count_after
  count_before=$(wc -l < "$lessons_file" | tr -d ' ')

  HOME="$fake_home" bash "$LOOPS_ROOT/install.sh" >/dev/null 2>&1
  count_after=$(wc -l < "$lessons_file" | tr -d ' ')

  if [ "$count_before" = "1" ] && [ "$count_after" = "1" ]; then
    record_result 16 "pass" "lessons.jsonl created idempotently; seeded line survives a second install"
  else
    record_result 16 "FAIL" "line count wrong: before=$count_before after=$count_after (want 1/1)"
  fi
}

test_criterion_17() {
  local d fake_home lessons_file
  d=$(fresh_tmp)
  fake_home="$d/home"
  mkdir -p "$fake_home"
  lessons_file="$fake_home/.claude/memory/lessons.jsonl"

  HOME="$fake_home" "$LOOPS_RUN" lesson record --category "test-cat" \
    --mistake "the mistake text" --correction "the correction text" >/dev/null 2>&1

  if [ ! -f "$lessons_file" ]; then
    record_result 17 "FAIL" "lessons.jsonl not created by lesson record"
    return
  fi

  local lines last_line cat mistake correction ts src
  lines=$(wc -l < "$lessons_file" | tr -d ' ')
  last_line=$(tail -n 1 "$lessons_file")
  cat=$(printf '%s' "$last_line" | jq -r '.category')
  mistake=$(printf '%s' "$last_line" | jq -r '.mistake')
  correction=$(printf '%s' "$last_line" | jq -r '.correction')
  ts=$(printf '%s' "$last_line" | jq -r '.ts')
  src=$(printf '%s' "$last_line" | jq -r '.source')

  local fail=""
  [ "$lines" != "1" ] && fail="$fail lines=$lines(want1)"
  [ "$cat" != "test-cat" ] && fail="$fail category=$cat"
  [ "$mistake" != "the mistake text" ] && fail="$fail mistake=$mistake"
  [ "$correction" != "the correction text" ] && fail="$fail correction=$correction"
  if [ -z "$ts" ] || [ "$ts" = "null" ]; then fail="$fail ts-missing"; fi
  [ "$src" != "" ] && fail="$fail source=$src(want empty when --source omitted)"

  if [ -z "$fail" ]; then
    record_result 17 "pass" "lesson record appends exactly one line, all fields round-trip"
  else
    record_result 17 "FAIL" "$fail"
  fi
}

test_criterion_18() {
  local d fake_home
  d=$(fresh_tmp)
  fake_home="$d/home"
  mkdir -p "$fake_home"

  HOME="$fake_home" "$LOOPS_RUN" lesson record --category "widget-parsing" \
    --mistake "the widget count field returns stale cached values" \
    --correction "always refetch the widget count live" >/dev/null 2>&1

  # exactly 1 non-stopword token shared with the entry (mistake+category) -> exit 1
  HOME="$fake_home" "$LOOPS_RUN" lesson check "check the field alignment issue" >/dev/null 2>&1
  local exit1=$?

  # exactly 2 non-stopword tokens shared -> exit 0
  HOME="$fake_home" "$LOOPS_RUN" lesson check "look at widget field mapping" >/dev/null 2>&1
  local exit2=$?

  if [ $exit1 -eq 1 ] && [ $exit2 -eq 0 ]; then
    record_result 18 "pass" "threshold observable: 1-token overlap exits 1, 2-token overlap exits 0"
  else
    record_result 18 "FAIL" "1-token-overlap exit=$exit1(want1) 2-token-overlap exit=$exit2(want0)"
  fi
}

test_criterion_19() {
  local d fake_home
  d=$(fresh_tmp)
  fake_home="$d/home"
  mkdir -p "$fake_home"

  HOME="$fake_home" "$LOOPS_RUN" lesson record --category "external-data-source" \
    --mistake "assumed cashPnl is net-of-fees in the polymarket PnL API reconcile field, but it is not" \
    --correction "cashPnl is net PnL after fees; use grossPnl for the gross settlement value" >/dev/null 2>&1

  HOME="$fake_home" "$LOOPS_RUN" lesson record --category "external-data-source" \
    --mistake "HL-side quantities are always NULL in the reconciliation dump; the exchange fills endpoint has the real values" \
    --correction "query the exchange fills endpoint directly for HL-side quantities, never trust the reconciliation dump" >/dev/null 2>&1

  local out1 exit1 exit2 exit3
  out1=$(HOME="$fake_home" "$LOOPS_RUN" lesson check "reconcile the polymarket PnL API cashPnl field" 2>&1)
  exit1=$?

  HOME="$fake_home" "$LOOPS_RUN" lesson check "rename a CSS variable" >/dev/null 2>&1
  exit2=$?

  # Hard negative: shares the generic token quantit* with lesson (b) but
  # nothing of its substance. Must stay quiet.
  HOME="$fake_home" "$LOOPS_RUN" lesson check "verify the quantity field is correct" >/dev/null 2>&1
  exit3=$?

  local fail=""
  [ "$exit1" -ne 0 ] && fail="$fail exit1=$exit1(want0)"
  echo "$out1" | grep -qF "grossPnl" || fail="$fail correctionA-not-printed"
  [ "$exit2" -ne 1 ] && fail="$fail exit2=$exit2(want1)"
  [ "$exit3" -ne 1 ] && fail="$fail exit3=$exit3(want1,hard-negative)"

  if [ -z "$fail" ]; then
    record_result 19 "pass" "seeded C1 lessons: real query matches, unrelated and hard-negative queries stay quiet"
  else
    record_result 19 "FAIL" "$fail"
  fi
}

test_criterion_20() {
  local file="$LOOPS_ROOT/.claude/agents/evaluator.md"
  local pattern='run\.sh lesson record --category external-data-source'

  if ! grep -qE "$pattern" "$file"; then
    record_result 20 "FAIL" "pattern not found in evaluator.md"
    return
  fi

  if ! check_anti_negation_guard "$file" "$pattern"; then
    record_result 20 "FAIL" "negation found in ±2 line window around the lesson-record instruction"
    return
  fi

  record_result 20 "pass" "evaluator.md instructs recording a lesson on external-data-source, no negation"
}

test_criterion_21() {
  local skill_file="$LOOPS_ROOT/.claude/skills/contract/SKILL.md"
  local boundary_file
  boundary_file=$(fresh_tmp)/boundary.txt
  awk '/^1\. \*\*Boundary\.\*\*/, /^2\. \*\*/{if (/^2\. \*\*/) next; print}' "$skill_file" > "$boundary_file"

  # Join wrapped lines into one so a phrase split across a line break by
  # markdown prose wrapping still matches as a contiguous string.
  local boundary_joined
  boundary_joined=$(fresh_tmp)/boundary_joined.txt
  tr '\n' ' ' < "$boundary_file" | tr -s ' ' > "$boundary_joined"

  local fail=""
  grep -qE 'run\.sh lesson check' "$boundary_file" || fail="$fail lesson-check-missing"
  grep -qF 'external-data-source' "$boundary_file" || fail="$fail external-data-source-missing"
  grep -qF "verify <external system>'s exact semantics via a live read-only check before locking" "$boundary_joined" \
    || fail="$fail required-criterion-phrase-missing"

  if [ -z "$fail" ] && ! check_anti_negation_guard "$boundary_file" 'run\.sh lesson check'; then
    fail="lesson-check-negated"
  fi

  if [ -z "$fail" ]; then
    record_result 21 "pass" "Boundary step wires lesson check + external-data-source to the mandatory criterion"
  else
    record_result 21 "FAIL" "$fail"
  fi
}

test_criterion_22() {
  local file="$LOOPS_ROOT/.claude/agents/planner.md"
  local pattern='run\.sh lesson check'

  if ! grep -qE "$pattern" "$file"; then
    record_result 22 "FAIL" "pattern not found in planner.md"
    return
  fi

  if ! check_anti_negation_guard "$file" "$pattern"; then
    record_result 22 "FAIL" "negation found in ±2 line window"
    return
  fi

  record_result 22 "pass" "planner.md consults the lesson store, no negation"
}

# Helper for criterion 23: check adversarial framing in evaluator.md (body-scoped,
# with special negation exception). Extracts body (after frontmatter closing ---),
# takes first 15 body lines, and verifies 'broken' and 'prove it' patterns each
# have at least one match surviving the anti-negation guard, with the literal phrase
# "not here to be helpful" treated as sanctioned (its "not" is the framing, not a hedge).
# Returns 0 on pass, 1 on fail.
check_criterion_23() {
  local target="$1"
  local body_file first15 sanitized

  # Extract body: skip frontmatter (first --- to closing ---)
  body_file=$(fresh_tmp)/c23_body.txt
  awk 'NR==1 && /^---[[:space:]]*$/ {c=1; next} c==1 && /^---[[:space:]]*$/ {c=2; next} c==2 {print}' "$target" > "$body_file"

  # Take first 15 body lines
  first15=$(fresh_tmp)/c23_first15.txt
  head -n 15 "$body_file" > "$first15"

  # Sanitize: replace "not here to be helpful" with a phrase that won't trigger negation guard
  sanitized=$(fresh_tmp)/c23_sanitized.txt
  sed 's/not here to be helpful/XXX here to be helpful/gI' "$first15" > "$sanitized"

  # Check both patterns survive the guard using the existing helper
  check_any_match_survives_guard "$sanitized" 'broken' || return 1
  check_any_match_survives_guard "$sanitized" 'prove it' || return 1
  return 0
}

test_criterion_23() {
  local real_file="$LOOPS_ROOT/.claude/agents/evaluator.md"

  # Check real file passes
  if ! check_criterion_23 "$real_file"; then
    record_result 23 "FAIL" "adversarial framing check fails on real evaluator.md"
    return
  fi

  # Sabotage tests on copies: all three must FAIL for criterion 23 to pass
  local sbx sab_a sab_b sab_c
  sbx=$(fresh_tmp)/c23_sandbox
  mkdir -p "$sbx"

  sab_a="$sbx/sab_a.md"
  sab_b="$sbx/sab_b.md"
  sab_c="$sbx/sab_c.md"

  # The "opening paragraph" is the first body paragraph that is not blank or a
  # heading (lines starting with #). State machine: after frontmatter, skip blank
  # and heading lines until first real paragraph text (state 3=deleting), skip
  # until blank (state 4=keep remaining content).

  # Sabotage (a): delete the opening paragraph entirely
  awk '
    NR==1 && /^---[[:space:]]*$/ {print; c=1; next}
    c==1 { print; if (/^---[[:space:]]*$/) {c=2}; next }
    c==2 {
      if (/^[[:space:]]*$/) { print; next }
      if (/^#/) { print; next }
      c=3; next
    }
    c==3 {
      if (/^[[:space:]]*$/) { c=4; next }
      next
    }
    c==4 { print }
  ' "$real_file" > "$sab_a"

  # Sabotage (b): reword opening paragraph to safe alternative
  awk '
    NR==1 && /^---[[:space:]]*$/ {print; c=1; next}
    c==1 { print; if (/^---[[:space:]]*$/) {c=2}; next }
    c==2 {
      if (/^[[:space:]]*$/) { print; next }
      if (/^#/) { print; next }
      print "Please review the work carefully and note any issues."
      c=3; next
    }
    c==3 {
      if (/^[[:space:]]*$/) { print; c=4; next }
      next
    }
    c==4 { print }
  ' "$real_file" > "$sab_b"

  # Sabotage (c): relocate opening below "## Output"
  # Capture the opening paragraph text to a temp file (BSD awk doesn't support -v with newlines)
  local para_file
  para_file="$sbx/para.txt"
  awk '
    NR==1 && /^---[[:space:]]*$/ {c=1; next}
    c==1 { if (/^---[[:space:]]*$/) {c=2}; next }
    c==2 {
      if (/^[[:space:]]*$/) { next }
      if (/^#/) { next }
      c=3; print; next
    }
    c==3 {
      if (/^[[:space:]]*$/) { exit }
      print
    }
  ' "$real_file" > "$para_file"

  # sab_a has the paragraph removed; insert it after "## Output"
  awk '
    { print }
    /^## Output/ && !done {
      print ""
      while ((getline line < "'"$para_file"'") > 0) {
        print line
      }
      close("'"$para_file"'")
      print ""
      done=1
    }
  ' "$sab_a" > "$sab_c"

  # Run sabotage checks: each MUST fail for criterion 23 to pass
  local fail_a fail_b fail_c
  check_criterion_23 "$sab_a" && fail_a="sab-a-passed(should-fail)"
  check_criterion_23 "$sab_b" && fail_b="sab-b-passed(should-fail)"
  check_criterion_23 "$sab_c" && fail_c="sab-c-passed(should-fail)"

  local fail=""
  [ -n "$fail_a" ] && fail="$fail $fail_a"
  [ -n "$fail_b" ] && fail="$fail $fail_b"
  [ -n "$fail_c" ] && fail="$fail $fail_c"

  if [ -z "$fail" ]; then
    record_result 23 "pass" "adversarial framing survives (body-scoped, first 15 lines, sabotage-proven)"
  else
    record_result 23 "FAIL" "sabotage probes failed:$fail"
  fi
}

# ============================================================================
# Phase 3 stubs (criteria 24–33 and 38)
# ============================================================================

test_criterion_24() {
  local skill_file="$LOOPS_ROOT/.claude/skills/worktree/SKILL.md"

  if [ ! -f "$skill_file" ]; then
    record_result 24 "FAIL" "worktree/SKILL.md not found"
    return
  fi

  # Check frontmatter name
  if ! grep -q '^name: worktree$' "$skill_file"; then
    record_result 24 "FAIL" "missing 'name: worktree' in frontmatter"
    return
  fi

  # Check that check, provision, fix subcommands are documented
  if ! grep -qi 'check' "$skill_file" || ! grep -qi 'provision' "$skill_file" || ! grep -qi 'fix' "$skill_file"; then
    record_result 24 "FAIL" "missing subcommand documentation"
    return
  fi

  # Check fail-closed documentation
  if ! grep -qi 'fail closed' "$skill_file" && ! grep -qi 'dirty tree' "$skill_file"; then
    record_result 24 "FAIL" "missing fail-closed / dirty tree documentation"
    return
  fi

  if ! grep -qi '\-\-force' "$skill_file"; then
    record_result 24 "FAIL" "missing --force flag documentation"
    return
  fi

  record_result 24 "pass" "worktree skill exists with correct structure"
}

test_criterion_25() {
  local d
  d=$(fresh_tmp)

  # All-hazards fixture
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  mkdir -p .git/hooks
  echo '#!/bin/bash
INSTALL_PYTHON=/Users/devashar/Documents/DS/arthur2.0/arthur/env/bin/python3.12
echo ok' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  git config core.hooksPath "$(pwd)/.git/hooks"

  touch .env
  git add file.txt
  git commit -qm "add file"
  echo "SECRET=123" >> .env

  mkdir -p node_modules
  echo "*" > .gitignore
  echo "node_modules/" >> .gitignore
  echo ".env" >> .gitignore

  local output_all before_status after_status
  before_status=$(git status --porcelain)
  output_all=$("$LOOPS_RUN" worktree check 2>&1)
  after_status=$(git status --porcelain)

  # Clean fixture
  local d2
  d2=$(fresh_tmp)
  cd "$d2"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  local output_clean
  output_clean=$("$LOOPS_RUN" worktree check 2>&1)

  # Strict-subset fixture (only 2 hazards)
  local d3
  d3=$(fresh_tmp)
  cd "$d3"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  mkdir -p .git/hooks
  echo '#!/bin/bash
INSTALL_PYTHON=/Users/devashar/Documents/DS/arthur2.0/arthur/env/bin/python3.12
echo ok' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  mkdir -p env
  echo "env/" > .gitignore

  local output_subset
  output_subset=$("$LOOPS_RUN" worktree check 2>&1)

  local fail=""
  # All-hazards fixture must have all four tokens
  echo "$output_all" | grep -q "HARDCODED_HOOK_PATH" || fail="$fail all:no-HARDCODED"
  echo "$output_all" | grep -q "HOOKS_PATH_ABSOLUTE" || fail="$fail all:no-ABSOLUTE"
  echo "$output_all" | grep -q "MISSING_ENV_FILE" || fail="$fail all:no-ENV"
  echo "$output_all" | grep -q "MISSING_BOOTSTRAP_ARTIFACT" || fail="$fail all:no-BOOTSTRAP"

  # Clean fixture must have none
  echo "$output_clean" | grep -q "HARDCODED_HOOK_PATH" && fail="$fail clean:has-HARDCODED"
  echo "$output_clean" | grep -q "HOOKS_PATH_ABSOLUTE" && fail="$fail clean:has-ABSOLUTE"
  echo "$output_clean" | grep -q "MISSING_ENV_FILE" && fail="$fail clean:has-ENV"
  echo "$output_clean" | grep -q "MISSING_BOOTSTRAP_ARTIFACT" && fail="$fail clean:has-BOOTSTRAP"

  # Subset fixture must have exactly two and NOT the other two
  echo "$output_subset" | grep -q "HARDCODED_HOOK_PATH" || fail="$fail subset:no-HARDCODED"
  echo "$output_subset" | grep -q "MISSING_BOOTSTRAP_ARTIFACT" || fail="$fail subset:no-BOOTSTRAP"
  echo "$output_subset" | grep -q "HOOKS_PATH_ABSOLUTE" && fail="$fail subset:has-ABSOLUTE"
  echo "$output_subset" | grep -q "MISSING_ENV_FILE" && fail="$fail subset:has-ENV"

  # Read-only check
  [ "$before_status" != "$after_status" ] && fail="$fail git-mutated"

  if [ -z "$fail" ]; then
    record_result 25 "pass" "worktree check emits correct hazard tokens"
  else
    record_result 25 "FAIL" "$fail"
  fi
}

test_criterion_26() {
  # Hazardous fixture - should fail without --force
  local d
  d=$(fresh_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  mkdir -p .git/hooks
  echo '#!/bin/bash
INSTALL_PYTHON=/Users/devashar/Documents/DS/arthur2.0/arthur/env/bin/python3.12
echo ok' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  local wt_count_before wt_count_after
  wt_count_before=$(git worktree list | wc -l | tr -d ' ')

  "$LOOPS_RUN" worktree provision test-branch >/dev/null 2>&1
  local exit_a=$?
  wt_count_after=$(git worktree list | wc -l | tr -d ' ')

  # Clean fixture - should succeed without --force
  local d2
  d2=$(fresh_tmp)
  cd "$d2"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  "$LOOPS_RUN" worktree provision clean-branch >/dev/null 2>&1
  local exit_b=$?

  local wt_exists=0
  [ -d ".claude/worktrees/clean-branch" ] && wt_exists=1

  local wt_in_list=0
  git worktree list | grep -q "clean-branch" && wt_in_list=1

  local fail=""
  [ $exit_a -eq 0 ] && fail="$fail hazardous→exit-0"
  [ "$wt_count_before" != "$wt_count_after" ] && fail="$fail hazardous-created-wt"
  [ $exit_b -ne 0 ] && fail="$fail clean→exit-nonzero"
  [ $wt_exists -eq 0 ] && fail="$fail clean:wt-dir-missing"
  [ $wt_in_list -eq 0 ] && fail="$fail clean:wt-not-in-list"

  if [ -z "$fail" ]; then
    record_result 26 "pass" "provision fails-closed on hazards, succeeds when clean"
  else
    record_result 26 "FAIL" "$fail"
  fi
}

test_criterion_27() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  mkdir -p .git/hooks
  echo '#!/bin/bash
INSTALL_PYTHON=/Users/devashar/Documents/DS/arthur2.0/arthur/env/bin/python3.12
echo ok' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  local output
  output=$("$LOOPS_RUN" worktree provision test-branch --force 2>&1)

  local wt_exists=0
  [ -d ".claude/worktrees/test-branch" ] && wt_exists=1

  local tokens_in_output=0
  echo "$output" | grep -q "HARDCODED_HOOK_PATH" && tokens_in_output=1

  local fail=""
  [ $wt_exists -eq 0 ] && fail="$fail wt-not-created"
  [ $tokens_in_output -eq 0 ] && fail="$fail tokens-not-printed"

  if [ -z "$fail" ]; then
    record_result 27 "pass" "provision --force creates worktree and prints hazards"
  else
    record_result 27 "FAIL" "$fail"
  fi
}

test_criterion_28() {
  # The rewriter only treats /Users/... and /home/... paths as candidates
  # (matching real machines), and the literal-prefix-match branch requires
  # the hardcoded path to actually start with the repo root. fresh_tmp()
  # lives under the OS temp dir (/var/folders/... on macOS), which does not
  # match either pattern, so this fixture must use fresh_home_tmp() (rooted
  # under $HOME/.cache) to exercise the real code path.
  local d
  d=$(fresh_home_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  # Create env dir to simulate real repo
  mkdir -p env/bin
  echo '#!/bin/bash
echo "mock python"' > env/bin/python3.12
  chmod +x env/bin/python3.12

  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<EOF
#!/bin/bash
INSTALL_PYTHON=$d/env/bin/python3.12
echo "running with \$INSTALL_PYTHON"
EOF
  chmod +x .git/hooks/pre-commit

  # Apply fix
  "$LOOPS_RUN" worktree fix --force >/dev/null 2>&1

  # (a) Syntax checks — fix() migrates the hook into tracked .githooks/
  local has_absolute has_show_toplevel is_executable parses_clean
  has_absolute=0
  has_show_toplevel=0
  is_executable=0
  parses_clean=0

  grep -q '/Users/\|/home/' .githooks/pre-commit 2>/dev/null && has_absolute=1
  grep -q '\-\-show-toplevel' .githooks/pre-commit 2>/dev/null && has_show_toplevel=1
  [ -x .githooks/pre-commit ] && is_executable=1
  bash -n .githooks/pre-commit 2>/dev/null && parses_clean=1

  # (b) Functional check - commit the migrated hook so it propagates to a
  # fresh linked worktree via checkout, then verify MAIN_WT resolves to the
  # MAIN worktree (not the linked one) from inside that linked worktree.
  git add .githooks/pre-commit >/dev/null 2>&1
  git commit -qm "migrate hook" >/dev/null 2>&1
  git worktree add .claude/worktrees/test-wt -b test-wt >/dev/null 2>&1

  local functional_works=0
  cd .claude/worktrees/test-wt
  # Extract and eval the path derivation from the checked-out hook
  main_wt_line=$(grep 'MAIN_WT.*git-common-dir' .githooks/pre-commit || echo "")
  if [ -n "$main_wt_line" ]; then
    eval "$main_wt_line"
    local resolved_python="$MAIN_WT/env/bin/python3.12"
    [ -x "$resolved_python" ] && functional_works=1
  fi
  cd "$d" >/dev/null

  local fail=""
  [ $has_absolute -eq 1 ] && fail="$fail has-absolute-path"
  [ $has_show_toplevel -eq 1 ] && fail="$fail has-show-toplevel"
  [ $is_executable -eq 0 ] && fail="$fail not-executable"
  [ $parses_clean -eq 0 ] && fail="$fail parse-error"
  [ $functional_works -eq 0 ] && fail="$fail functional-check-failed"

  # (c) Edge-case path rewrites: 4-component, deep, spaces, out-of-repo.
  # Each sub-case gets a fresh fixture so failures don't cascade.
  local d4 ddeep dspace doutside

  # 4-component path (e.g. /Users/x/y/tool) — the old heuristic dropped the
  # filename entirely here because it assumed 5 path components.
  d4=$(fresh_home_tmp)
  (
    cd "$d4"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    touch file.txt && git add file.txt && git commit -qm "init"
    mkdir -p x/y
    echo "mock4" > x/y/tool
    chmod +x x/y/tool
    mkdir -p .git/hooks
    cat > .git/hooks/test-4comp <<EOF
#!/bin/bash
T=$d4/x/y/tool
\$T
EOF
    chmod +x .git/hooks/test-4comp
    "$LOOPS_RUN" worktree fix --force >/dev/null 2>&1
  )
  local c4_rewrite
  c4_rewrite=$(grep -o '\$MAIN_WT/x/y/tool' "$d4/.githooks/test-4comp" 2>/dev/null || echo "")
  [ -z "$c4_rewrite" ] && fail="$fail 4comp-lost-filename"

  # Deep path (many components)
  ddeep=$(fresh_home_tmp)
  (
    cd "$ddeep"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    touch file.txt && git add file.txt && git commit -qm "init"
    mkdir -p a/b/c/d/e
    echo "mockdeep" > a/b/c/d/e/deep
    chmod +x a/b/c/d/e/deep
    mkdir -p .git/hooks
    cat > .git/hooks/test-deep <<EOF
#!/bin/bash
D=$ddeep/a/b/c/d/e/deep
\$D
EOF
    chmod +x .git/hooks/test-deep
    "$LOOPS_RUN" worktree fix --force >/dev/null 2>&1
  )
  local deep_rewrite
  deep_rewrite=$(grep -o '\$MAIN_WT/a/b/c/d/e/deep' "$ddeep/.githooks/test-deep" 2>/dev/null || echo "")
  [ -z "$deep_rewrite" ] && fail="$fail deep-path-corrupted"

  # Path containing spaces — the matched region stops at the space, but the
  # untouched remainder of the line is preserved verbatim, so the
  # reconstructed line must still contain the full original suffix.
  dspace=$(fresh_home_tmp)
  (
    cd "$dspace"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    touch file.txt && git add file.txt && git commit -qm "init"
    mkdir -p "dir with spaces"
    echo "mockspace" > "dir with spaces/file with spaces"
    chmod +x "dir with spaces/file with spaces"
    mkdir -p .git/hooks
    cat > .git/hooks/test-spaces <<EOF
#!/bin/bash
S="$dspace/dir with spaces/file with spaces"
echo "\$S"
EOF
    chmod +x .git/hooks/test-spaces
    "$LOOPS_RUN" worktree fix --force >/dev/null 2>&1
  )
  local spaces_ok=0
  if [ -f "$dspace/.githooks/test-spaces" ]; then
    bash -n "$dspace/.githooks/test-spaces" 2>/dev/null && \
      grep -q 'dir with spaces/file with spaces' "$dspace/.githooks/test-spaces" 2>/dev/null && \
      spaces_ok=1
  fi
  [ $spaces_ok -eq 0 ] && fail="$fail spaces-path-corrupted"

  # Path outside repo root — must fail loudly, exit non-zero, leave the hook
  # byte-unchanged, and never migrate it into .githooks/.
  doutside=$(fresh_home_tmp)
  (
    cd "$doutside"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    touch file.txt && git add file.txt && git commit -qm "init"
    mkdir -p .git/hooks
    # Must contain a literal /Users/ or /home/ segment to enter the rewriter
    # at all (that's the hazard prefilter), while NOT sharing the repo root
    # prefix — e.g. a tool installed under a different user's home directory.
    cat > .git/hooks/test-outside <<'HOOKEOF'
#!/bin/bash
O=/Users/some-other-user/bin/python3.12
$O
HOOKEOF
    chmod +x .git/hooks/test-outside
    original_hash=$(shasum -a 256 .git/hooks/test-outside | awk '{print $1}')
    "$LOOPS_RUN" worktree fix --force >/dev/null 2>&1
    fix_exit=$?
    after_hash=$(shasum -a 256 .git/hooks/test-outside | awk '{print $1}')
    echo "$fix_exit $original_hash $after_hash"
  ) > "$SUITE_TMPDIR/c28_outside_result" 2>/dev/null
  read -r out_exit out_hash_before out_hash_after < "$SUITE_TMPDIR/c28_outside_result"
  [ "$out_exit" = "0" ] && fail="$fail outside-path-did-not-fail"
  [ "$out_hash_before" != "$out_hash_after" ] && fail="$fail outside-path-hook-modified"
  [ -f "$doutside/.githooks/test-outside" ] && fail="$fail outside-path-hook-migrated"

  if [ -z "$fail" ]; then
    record_result 28 "pass" "fix remediates HARDCODED_HOOK_PATH correctly"
  else
    record_result 28 "FAIL" "$fail"
  fi
}

test_criterion_29() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  # Set absolute hooksPath
  git config core.hooksPath "$(pwd)/.git/hooks"

  "$LOOPS_RUN" worktree fix --force >/dev/null 2>&1

  local hooks_path_after
  hooks_path_after=$(git config --get core.hooksPath 2>/dev/null || echo "")

  local check_output
  check_output=$("$LOOPS_RUN" worktree check 2>&1)

  local fail=""
  [ -n "$hooks_path_after" ] && fail="$fail hooksPath-still-set"
  echo "$check_output" | grep -q "HOOKS_PATH_ABSOLUTE" && fail="$fail check-still-emits-token"

  if [ -z "$fail" ]; then
    record_result 29 "pass" "fix remediates HOOKS_PATH_ABSOLUTE"
  else
    record_result 29 "FAIL" "$fail"
  fi
}

test_criterion_30() {
  local d
  d=$(fresh_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > file.txt
  git add file.txt
  git commit -qm "init"

  # Seed all secret patterns
  touch .env .env.local secret.pem private.key mysecret.txt credential.json
  touch id_rsa id_ed25519 .npmrc .netrc .pgpass secrets.tfvars
  touch cert.p12 cert.pfx keystore.jks app.keystore
  touch my-service-account.json app-sa.json gcloud-prod.json

  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<'EOF'
#!/bin/bash
INSTALL_PYTHON=/Users/devashar/Documents/DS/arthur2.0/arthur/env/bin/python3.12
echo ok
EOF
  chmod +x .git/hooks/pre-commit

  # Create a stub gh command
  local stub_dir
  stub_dir=$(fresh_tmp)/bin
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<'GHSTUB'
#!/bin/bash
echo "https://github.com/test/test/pull/1"
GHSTUB
  chmod +x "$stub_dir/gh"

  # Apply fix and attempt PR
  PATH="$stub_dir:$PATH" "$LOOPS_RUN" worktree provision test-branch --pr >/dev/null 2>&1 || true

  # Check staged/committed state IN THE WORKTREE
  cd .claude/worktrees/test-branch
  local staged
  staged=$(git diff --cached --name-only 2>/dev/null || echo "")

  # Check committed files
  local committed
  committed=$(git log --name-only --pretty=format: HEAD 2>/dev/null | grep -v '^$' || echo "")

  local fail=""
  echo "$staged" | grep -Eq '\\.env|\\*\\.pem|\\.key|secret|credential|id_rsa|id_ed25519|\\.npmrc|\\.netrc|\\.pgpass|\\.tfvars|\\.p12|\\.pfx|keystore|\\.jks|service-account|\-sa\\.json|gcloud-' && fail="$fail secret-in-staged"
  echo "$committed" | grep -Eq '\\.env|\\*\\.pem|\\.key|secret|credential|id_rsa|id_ed25519|\\.npmrc|\\.netrc|\\.pgpass|\\.tfvars|\\.p12|\\.pfx|keystore|\\.jks|service-account|\-sa\\.json|gcloud-' && fail="$fail secret-in-committed"

  # Return to ORIGINAL fixture to check that secret files remain untracked THERE
  cd "$d"
  local untracked
  untracked=$(git ls-files --others --exclude-standard)

  # Verify secret files are untracked in the original fixture
  for secret_file in .env .env.local secret.pem private.key mysecret.txt credential.json id_rsa id_ed25519 .npmrc .netrc .pgpass secrets.tfvars cert.p12 cert.pfx keystore.jks app.keystore my-service-account.json app-sa.json gcloud-prod.json; do
    echo "$untracked" | grep -q "$secret_file" || fail="$fail $secret_file-not-untracked"
  done

  if [ -z "$fail" ]; then
    record_result 30 "pass" "secrets never staged or committed"
  else
    record_result 30 "FAIL" "$fail"
  fi
}

test_criterion_31() {
  # Fixture requires $HOME-rooted path to trigger HARDCODED_HOOK_PATH hazard
  # (prefilter looks for /Users/|/home/), and the hardcoded path must share
  # repo-root as literal prefix so fix() succeeds cleanly (no fail-loud on
  # out-of-repo path). The original literal "/Users/devashar/.../arthur/..."
  # was relying on the old heuristic fallback (now correctly removed).
  local d
  d=$(fresh_home_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > file.txt
  git add file.txt
  git commit -qm "init"

  mkdir -p .loops
  echo "# Log" > .loops/log.md

  # Create subset fixture (only HARDCODED_HOOK_PATH and MISSING_BOOTSTRAP_ARTIFACT)
  mkdir -p env/bin
  echo '#!/bin/bash
echo "mock python"' > env/bin/python3.12
  chmod +x env/bin/python3.12

  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<EOF
#!/bin/bash
INSTALL_PYTHON=$d/env/bin/python3.12
echo ok
EOF
  chmod +x .git/hooks/pre-commit

  echo "env/" > .gitignore

  # Stub gh command
  local stub_dir argv_file
  stub_dir=$(fresh_tmp)/bin
  argv_file=$(fresh_tmp)/gh_argv.txt
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<GHSTUB
#!/bin/bash
echo "\$@" > "$argv_file"
echo "https://github.com/test/test/pull/123"
GHSTUB
  chmod +x "$stub_dir/gh"

  # Run provision --pr
  PATH="$stub_dir:$PATH" bash "$LOOPS_ROOT/run.sh" worktree provision test-branch --pr >/dev/null 2>&1 || true

  # Check commit diff
  local commit_diff
  cd .claude/worktrees/test-branch 2>/dev/null || { record_result 31 "FAIL" "worktree not created"; return; }
  commit_diff=$(git show --name-only --pretty=format: HEAD 2>/dev/null || echo "")

  # Check log contains PR URL
  cd "$d"
  local log_has_url=0
  grep -q "https://github.com/test/test/pull/123" .loops/log.md 2>/dev/null && log_has_url=1

  # Check gh argv
  local argv
  argv=$(cat "$argv_file" 2>/dev/null || echo "")

  local fail=""
  [ -z "$commit_diff" ] && fail="$fail empty-commit-diff"
  echo "$commit_diff" | grep -q "pre-commit" || fail="$fail hook-not-in-diff"
  [ $log_has_url -eq 0 ] && fail="$fail url-not-in-log"
  echo "$argv" | grep -q "\-\-draft" || fail="$fail no-draft-flag"
  echo "$argv" | grep -q "HARDCODED_HOOK_PATH" || fail="$fail body-missing-HARDCODED"
  echo "$argv" | grep -q "MISSING_BOOTSTRAP_ARTIFACT" || fail="$fail body-missing-BOOTSTRAP"
  echo "$argv" | grep -q "HOOKS_PATH_ABSOLUTE" && fail="$fail body-has-untriggered-ABSOLUTE"
  echo "$argv" | grep -q "MISSING_ENV_FILE" && fail="$fail body-has-untriggered-ENV"

  if [ -z "$fail" ]; then
    record_result 31 "pass" "provision --pr creates commit, PR with correct body, logs URL"
  else
    record_result 31 "FAIL" "$fail"
  fi
}

test_criterion_32() {
  # (a) Orphaned worktree fixture
  local d
  d=$(fresh_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  git worktree add .claude/worktrees/orphan-wt -b orphan-wt >/dev/null 2>&1
  rm -rf .claude/worktrees/orphan-wt

  local output_default
  output_default=$("$LOOPS_RUN" worktree reap 2>&1)

  local wt_entry_before wt_entry_after
  wt_entry_before=$(ls .git/worktrees/ 2>/dev/null | wc -l | tr -d ' ')

  "$LOOPS_RUN" worktree reap --prune >/dev/null 2>&1

  wt_entry_after=$(ls .git/worktrees/ 2>/dev/null | wc -l | tr -d ' ')

  # (b) Clean fixture
  local d2
  d2=$(fresh_tmp)
  cd "$d2"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -qm "init"

  git worktree add .claude/worktrees/live-wt -b live-wt >/dev/null 2>&1

  local output_clean
  output_clean=$("$LOOPS_RUN" worktree reap 2>&1)

  local fail=""
  echo "$output_default" | grep -q "orphan-wt" || fail="$fail default-didnt-report-orphan"
  [ "$wt_entry_before" -eq 0 ] && fail="$fail orphan-entry-missing-before-prune"
  [ "$wt_entry_after" -ne 0 ] && fail="$fail prune-didnt-remove-entry"
  echo "$output_clean" | grep -qi "orphan" && fail="$fail clean-reported-orphan"
  echo "$output_clean" | grep -q "live-wt" && fail="$fail clean-named-live-wt"

  if [ -z "$fail" ]; then
    record_result 32 "pass" "reap reports orphans, prunes only with --prune"
  else
    record_result 32 "FAIL" "$fail"
  fi
}

test_criterion_33() {
  # IDENTITY: Does not remediate real user repos.
  # Snapshots were captured at suite start; compare now.
  local repos=(
    "$HOME/Documents/DS/data-catalog"
    "$HOME/Documents/DS/data-solutions-kujata"
    "$HOME/Documents/DS/plugins/runbooks"
    "$HOME/Documents/DS/workspace/infrastructure"
    "$HOME/Documents/DS/arthur2.0/petrichor"
    "$HOME/Documents/DS/arthur2.0/arthur"
  )

  local fail=""
  local skipped=""
  for repo in "${repos[@]}"; do
    if [ ! -d "$repo" ]; then
      skipped="$skipped $(basename "$repo")"
      continue
    fi

    local repo_basename=$(basename "$repo")
    local snapshot_status="$DOWNSTREAM_SNAPSHOTS/${repo_basename}.status"
    local snapshot_head="$DOWNSTREAM_SNAPSHOTS/${repo_basename}.head"

    if [ ! -f "$snapshot_status" ] || [ ! -f "$snapshot_head" ]; then
      fail="$fail ${repo_basename}:no-snapshot"
      continue
    fi

    local status_before status_after head_before head_after
    status_before=$(cat "$snapshot_status")
    head_before=$(cat "$snapshot_head")
    status_after=$(cd "$repo" && git status --porcelain 2>/dev/null)
    head_after=$(cd "$repo" && git rev-parse HEAD 2>/dev/null)

    [ "$status_before" != "$status_after" ] && fail="$fail ${repo_basename}:status-changed"
    [ "$head_before" != "$head_after" ] && fail="$fail ${repo_basename}:head-changed"
  done

  if [ -z "$fail" ]; then
    local msg="no remediation against real repos"
    [ -n "$skipped" ] && msg="$msg (skipped:$skipped)"
    record_result 33 "pass" "$msg"
  else
    record_result 33 "FAIL" "$fail"
  fi
}

test_criterion_38() {
  # (a) Static check
  local static_fail=""
  grep -q 'git add -A' "$LOOPS_RUN" && static_fail="$static_fail has-git-add-A"
  grep -q 'git add \.' "$LOOPS_RUN" && static_fail="$static_fail has-git-add-dot"
  grep -q 'git add -u' "$LOOPS_RUN" && static_fail="$static_fail has-git-add-u"
  grep -q 'git commit -a' "$LOOPS_RUN" && static_fail="$static_fail has-git-commit-a"
  grep -q 'commit -am' "$LOOPS_RUN" && static_fail="$static_fail has-commit-am"

  # (b) Behavioral check
  # Fixture requires $HOME-rooted path to trigger HARDCODED_HOOK_PATH hazard
  # (prefilter looks for /Users/|/home/), and the hardcoded path must share
  # repo-root as literal prefix so fix() succeeds cleanly (no fail-loud on
  # out-of-repo path). The original literal "/Users/devashar/.../arthur/..."
  # was relying on the old heuristic fallback (now correctly removed).
  local d
  d=$(fresh_home_tmp)
  cd "$d"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > file.txt
  git add file.txt
  git commit -qm "init"

  # Create unrelated dirty tracked file
  echo "tracked change" > file.txt

  # Create unrelated untracked file
  echo "untracked" > unrelated.txt

  mkdir -p .loops
  echo "# Log" > .loops/log.md

  mkdir -p env/bin
  echo '#!/bin/bash
echo "mock python"' > env/bin/python3.12
  chmod +x env/bin/python3.12

  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<EOF
#!/bin/bash
INSTALL_PYTHON=$d/env/bin/python3.12
echo ok
EOF
  chmod +x .git/hooks/pre-commit

  # Stub gh
  local stub_dir
  stub_dir=$(fresh_tmp)/bin
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<'GHSTUB'
#!/bin/bash
echo "https://github.com/test/test/pull/1"
GHSTUB
  chmod +x "$stub_dir/gh"

  PATH="$stub_dir:$PATH" bash "$LOOPS_ROOT/run.sh" worktree provision test-branch --pr >/dev/null 2>&1 || true

  cd .claude/worktrees/test-branch 2>/dev/null || { record_result 38 "FAIL" "worktree not created"; return; }

  local committed_files
  committed_files=$(git show --name-only --pretty=format: HEAD 2>/dev/null || echo "")

  # Check unrelated files are still dirty/untracked
  cd "$d"
  local file_status unrelated_status
  file_status=$(git status --porcelain file.txt 2>/dev/null | awk '{print $1}')
  unrelated_status=$(git status --porcelain unrelated.txt 2>/dev/null | awk '{print $1}')

  local fail="$static_fail"
  echo "$committed_files" | grep -q "file.txt" && fail="$fail committed-unrelated-tracked"
  echo "$committed_files" | grep -q "unrelated.txt" && fail="$fail committed-unrelated-untracked"
  [ "$file_status" != "M" ] && fail="$fail file.txt-not-dirty-after"
  [ "$unrelated_status" != "??" ] && fail="$fail unrelated.txt-not-untracked-after"

  if [ -z "$fail" ]; then
    record_result 38 "pass" "no blanket staging: explicit paths only"
  else
    record_result 38 "FAIL" "$fail"
  fi
}

# ============================================================================
# Phase 4 stubs (criteria 34–37)
# ============================================================================

test_criterion_34() { record_result 34 "FAIL" "not yet implemented (phase 4)"; }
test_criterion_35() { record_result 35 "FAIL" "not yet implemented (phase 4)"; }
test_criterion_36() { record_result 36 "FAIL" "not yet implemented (phase 4)"; }
test_criterion_37() { record_result 37 "FAIL" "not yet implemented (phase 4)"; }

# ============================================================================
# Main execution
# ============================================================================

# Create the suite temp root once; all helpers allocate under it
SUITE_TMPDIR=$(mktemp -d)
HOME_TMPDIR_REGISTRY="$SUITE_TMPDIR/home_dirs.txt"
: > "$HOME_TMPDIR_REGISTRY"

# Capture initial git status (immutability guard)
INITIAL_GIT_STATUS=$(cd "$LOOPS_ROOT" && git status --porcelain 2>/dev/null)

# Snapshot downstream repos for criterion 33 (no-remediation-against-real-repos)
DOWNSTREAM_REPOS=(
  "$HOME/Documents/DS/data-catalog"
  "$HOME/Documents/DS/data-solutions-kujata"
  "$HOME/Documents/DS/plugins/runbooks"
  "$HOME/Documents/DS/workspace/infrastructure"
  "$HOME/Documents/DS/arthur2.0/petrichor"
  "$HOME/Documents/DS/arthur2.0/arthur"
)
DOWNSTREAM_SNAPSHOTS="$SUITE_TMPDIR/downstream_snapshots"
mkdir -p "$DOWNSTREAM_SNAPSHOTS"
for repo_path in "${DOWNSTREAM_REPOS[@]}"; do
  if [ -d "$repo_path" ]; then
    repo_basename=$(basename "$repo_path")
    (cd "$repo_path" && git status --porcelain 2>/dev/null) > "$DOWNSTREAM_SNAPSHOTS/${repo_basename}.status" || true
    (cd "$repo_path" && git rev-parse HEAD 2>/dev/null) > "$DOWNSTREAM_SNAPSHOTS/${repo_basename}.head" || true
  fi
done

# Capture the REAL global lesson store (unstubbed $HOME) — every lesson test
# above stubs its own $HOME, but this is the guard that proves none of them
# leaked through to the actual machine-wide store.
REAL_LESSONS_FILE="$HOME/.claude/memory/lessons.jsonl"
if [ -f "$REAL_LESSONS_FILE" ]; then
  INITIAL_LESSONS_CONTENT=$(cat "$REAL_LESSONS_FILE")
else
  INITIAL_LESSONS_CONTENT="__ABSENT__"
fi

# Run all criteria in ascending order; criterion 1 (meta-check) runs first
test_criterion_1
for n in $(seq 2 38); do
  test_criterion_$n
done

# Verify the loops repo is unchanged
FINAL_GIT_STATUS=$(cd "$LOOPS_ROOT" && git status --porcelain 2>/dev/null)
if [ "$INITIAL_GIT_STATUS" != "$FINAL_GIT_STATUS" ]; then
  echo "[FAIL] suite mutated the loops repo git status"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Verify the REAL global lesson store is byte-identical
if [ -f "$REAL_LESSONS_FILE" ]; then
  FINAL_LESSONS_CONTENT=$(cat "$REAL_LESSONS_FILE")
else
  FINAL_LESSONS_CONTENT="__ABSENT__"
fi
if [ "$INITIAL_LESSONS_CONTENT" != "$FINAL_LESSONS_CONTENT" ]; then
  echo "[FAIL] suite mutated the real ~/.claude/memory/lessons.jsonl"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Final tally (denominator 37 = criteria 2..38)
echo "$PASS_COUNT/$TOTAL passed"

[ $FAIL_COUNT -eq 0 ] && exit 0 || exit 1
