#!/usr/bin/env bash
# Behavioral tests for scripts/check-anchors.sh.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/scripts/check-anchors.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

expect_ok() {
  local output
  output=$("$CHECKER" "$1" "$2" 2>&1) || fail "expected success for $1: $output"
  [ "$output" = "$3" ] || fail "unexpected success output for $1: $output"
}

expect_failure() {
  local output
  if output=$("$CHECKER" "$1" "$2" 2>&1); then
    fail "expected failure for $1: $output"
  fi
  printf '%s\n' "$output" | grep -Fq "$3" || fail "missing failure text for $1: $output"
}

mkdir -p "$TMP/repo"
printf '%s\n' 'alpha line' 'beta line' > "$TMP/repo/source.txt"
printf '%s\n' \
  'source.txt:1 — "alpha line"' \
  "source.txt:2 - 'beta line'" > "$TMP/good.txt"
expect_ok "$TMP/good.txt" "$TMP/repo" 'ANCHORS_OK 2'

printf '%s\n' "He said don't stop." > "$TMP/repo/apostrophe.txt"
printf '%s\n' 'apostrophe.txt:1 — "He said don'"'"'t stop."' > "$TMP/apostrophe.txt"
expect_ok "$TMP/apostrophe.txt" "$TMP/repo" 'ANCHORS_OK 1'

printf '%s\n' 'source.txt:1 — “alpha line”' > "$TMP/curly-double.txt"
expect_ok "$TMP/curly-double.txt" "$TMP/repo" 'ANCHORS_OK 1'

printf '%s\n' 'source.txt:1 — ‘alpha line’' > "$TMP/curly-single.txt"
expect_ok "$TMP/curly-single.txt" "$TMP/repo" 'ANCHORS_OK 1'

printf '%s\n' 'source.txt:1 — ""' > "$TMP/empty.txt"
expect_failure "$TMP/empty.txt" "$TMP/repo" 'empty snippet'

printf '%s\n' '../outside.txt:1 — "outside"' > "$TMP/traversal.txt"
printf '%s\n' outside > "$TMP/outside.txt"
expect_failure "$TMP/traversal.txt" "$TMP/repo" 'outside repo root'

printf '%s\n' 'source.txt:9 — "alpha line"' > "$TMP/bad-line.txt"
expect_failure "$TMP/bad-line.txt" "$TMP/repo" 'line out of range'

printf '%s\n' 'source.txt:1 — "wrong snippet"' > "$TMP/wrong-snippet.txt"
expect_failure "$TMP/wrong-snippet.txt" "$TMP/repo" 'wrong snippet'

printf '%s\n' 'missing.txt:1 — "missing"' > "$TMP/missing-file.txt"
expect_failure "$TMP/missing-file.txt" "$TMP/repo" 'missing file'

printf '%s\n' 'This report has no evidence.' > "$TMP/zero.txt"
expect_failure "$TMP/zero.txt" "$TMP/repo" 'zero anchors'

printf '%s\n' \
  'source.txt:1 — "alpha line"' \
  'This is likely unverified.' > "$TMP/hedge.txt"
expect_failure "$TMP/hedge.txt" "$TMP/repo" 'hedge word'

printf '%s\n' \
  'source.txt:1 — "alpha line"' \
  'NOT CHECKED: likely, path assumed, implicit.' > "$TMP/not-checked.txt"
expect_ok "$TMP/not-checked.txt" "$TMP/repo" 'ANCHORS_OK 1'

printf 'CHECK_ANCHORS_OK\n'
