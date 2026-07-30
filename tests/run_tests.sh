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

cleanup() {
  [ -n "$SUITE_TMPDIR" ] && [ -d "$SUITE_TMPDIR" ] && rm -rf "$SUITE_TMPDIR"
}
trap cleanup EXIT

# Allocate a fresh scratch directory
fresh_tmp() {
  local d
  d=$(mktemp -d "$SUITE_TMPDIR/testXXXXXX")
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
# Phase 2 stubs (criteria 16–23)
# ============================================================================

test_criterion_16() { record_result 16 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_17() { record_result 17 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_18() { record_result 18 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_19() { record_result 19 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_20() { record_result 20 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_21() { record_result 21 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_22() { record_result 22 "FAIL" "not yet implemented (phase 2)"; }
test_criterion_23() { record_result 23 "FAIL" "not yet implemented (phase 2)"; }

# ============================================================================
# Phase 3 stubs (criteria 24–33 and 38)
# ============================================================================

test_criterion_24() { record_result 24 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_25() { record_result 25 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_26() { record_result 26 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_27() { record_result 27 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_28() { record_result 28 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_29() { record_result 29 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_30() { record_result 30 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_31() { record_result 31 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_32() { record_result 32 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_33() { record_result 33 "FAIL" "not yet implemented (phase 3)"; }
test_criterion_38() { record_result 38 "FAIL" "not yet implemented (phase 3)"; }

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

# Capture initial git status (immutability guard)
INITIAL_GIT_STATUS=$(cd "$LOOPS_ROOT" && git status --porcelain 2>/dev/null)

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

# Final tally (denominator 37 = criteria 2..38)
echo "$PASS_COUNT/$TOTAL passed"

[ $FAIL_COUNT -eq 0 ] && exit 0 || exit 1
