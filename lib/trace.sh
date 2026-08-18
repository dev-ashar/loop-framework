#!/usr/bin/env bash

# LOOPS trace protocol. The run.sh orchestrator owns authoritative lifecycle events.

TRACE_FILE=".loops/trace.jsonl"
TRACE_STATE_FILE=".loops/trace.state"
TRACE_LOCK_DIR=".loops/trace.lock"
TRACE_USAGE_START='usage: trace start --run-id <id> --correlation-id <id> [--iteration <n>] [--task <text>] [--worktree <path>]'
TRACE_USAGE_EMIT='usage: trace emit --phase <phase> --status <status> [--role <role>] [--score <number>] [--verdict <verdict>] [--gap <text>] [--task <text>] [--worktree <path>]'
TRACE_USAGE_END='usage: trace end --verdict BLOCK [--gap <text>] [--status <status>]'
TRACE_USAGE_VALIDATE='usage: trace validate <path>'

trace_schema_filter() {
  cat <<'JQ'
def valid_string: type == "string" and length > 0;
def valid_integer: type == "number" and floor == .;
def valid_event:
  type == "object"
  and ((keys_unsorted - ["schemaVersion","eventId","runId","sequence","timestamp","iteration","role","phase","status","correlationId","contractHash","score","verdict","gap","task","worktree"]) | length == 0)
  and has("schemaVersion") and has("eventId") and has("runId") and has("sequence") and has("timestamp") and has("iteration") and has("role") and has("phase") and has("status") and has("correlationId") and has("contractHash")
  and (.schemaVersion == 1)
  and (.eventId | valid_string)
  and (.runId | valid_string)
  and (.sequence | valid_integer and . >= 1)
  and (.timestamp | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"))
  and (.iteration | valid_integer and . >= 0)
  and (.role | valid_string)
  and (.phase | valid_string)
  and (.status | valid_string)
  and (.correlationId | valid_string)
  and (.contractHash | type == "string" and test("^[0-9a-fA-F]{64}$"))
  and ((has("score") | not) or (.score | type == "number" and isfinite))
  and ((has("verdict") | not) or (.verdict | valid_string))
  and ((has("gap") | not) or (.gap | valid_string))
  and ((has("task") | not) or (.task | valid_string))
  and ((has("worktree") | not) or (.worktree | (type == "string" and length > 0 or type == "object")));
JQ
}

trace_contract_hash() {
  local contract_file=".loops/contract.md"
  [ -f "$contract_file" ] || {
    printf '%s\n' 'trace: .loops/contract.md is missing' >&2
    return 1
  }
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$contract_file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$contract_file" | awk '{print $1}'
  else
    printf '%s\n' 'trace: no SHA-256 utility is available' >&2
    return 1
  fi
}

trace_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

trace_new_id() {
  local value
  if command -v uuidgen >/dev/null 2>&1; then
    if value=$(uuidgen 2>/dev/null); then
      printf '%s\n' "$value"
      return 0
    fi
  fi
  printf 'trace-%s-%s-%s\n' "$(date -u +%s)" "$$" "$RANDOM"
}

trace_validate_file() {
  local file="${1:-$TRACE_FILE}" expected_hash explicit=0
  [ "$#" -eq 0 ] || explicit=1
  if [ ! -f "$file" ]; then
    [ "$explicit" -eq 0 ] && return 0
    printf 'trace: file not found: %s\n' "$file" >&2
    return 1
  fi
  [ -s "$file" ] || {
    printf 'trace: file is empty: %s\n' "$file" >&2
    return 1
  }
  if ! python3 - "$file" <<'PY'
import json
import sys
with open(sys.argv[1], newline="") as handle:
    rows = handle.read().splitlines(keepends=True)
if not rows or any(not row.strip() or row.endswith("\n\n") for row in rows):
    raise SystemExit(1)
for row in rows:
    json.loads(row.rstrip("\r\n"))
PY
  then
    printf 'trace: invalid physical JSONL lines: %s\n' "$file" >&2
    return 1
  fi
  if ! expected_hash=$(trace_contract_hash); then
    return 1
  fi
  if ! jq -e -s "$(trace_schema_filter)
    all(.[]; valid_event)
    and ([.[].eventId] | length == (unique | length))
    and (reduce .[] as \$event ({}; .[\$event.runId] += [\$event])
      | all(.[];
          ([.[].correlationId] | unique | length == 1)
          and ([.[].contractHash] | unique | length == 1)
          and ([.[].iteration] | unique | length == 1)
          and (map(.sequence) as \$sequences
            | \$sequences == [range(1; (\$sequences | length) + 1)])
        ))
  " "$file" >/dev/null 2>&1; then
    printf 'trace: invalid JSONL or non-monotonic trace: %s\n' "$file" >&2
    return 1
  fi
  if [ -f "$TRACE_STATE_FILE" ]; then
    local active_run active_correlation active_iteration active_hash
    if ! active_run=$(trace_state_value runId) || ! active_correlation=$(trace_state_value correlationId) \
      || ! active_iteration=$(trace_state_value iteration) || ! active_hash=$(trace_state_value contractHash); then
      printf 'trace: active run state is malformed\n' >&2
      return 1
    fi
    [ "$active_hash" = "$expected_hash" ] || {
      printf '%s\n' 'trace: locked contract hash changed' >&2
      return 1
    }
    if ! jq -e -s --arg run "$active_run" --arg correlation "$active_correlation" \
      --arg iteration "$active_iteration" --arg hash "$active_hash" '
      [.[].runId] as $runs
      | ($runs | index($run)) as $first
      | ($first != null and all($runs[$first:][]; . == $run))
      and ([.[] | select(.runId == $run)] | length > 0)
      and (all(.[] | select(.runId == $run);
          .correlationId == $correlation and
          (.iteration | tostring) == $iteration and
          .contractHash == $hash))
    ' "$file" >/dev/null 2>&1; then
      printf 'trace: active run history is interleaved or inconsistent\n' >&2
      return 1
    fi
  fi
}

trace_lock() {
  local attempt=0
  while ! mkdir "$TRACE_LOCK_DIR" 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 10000 ] || {
      printf '%s\n' 'trace: timed out waiting for trace lock' >&2
      return 1
    }
    sleep 0.01
  done
}

trace_unlock() {
  rmdir "$TRACE_LOCK_DIR" 2>/dev/null || true
}

trace_state_valid() {
  [ -f "$TRACE_STATE_FILE" ] || {
    printf '%s\n' 'trace: no active run; use trace start first' >&2
    return 1
  }
  jq -e '
    type == "object" and
    (keys_unsorted - ["runId","correlationId","iteration","contractHash"] | length == 0) and
    has("runId") and has("correlationId") and has("iteration") and has("contractHash") and
    (.runId | type == "string" and length > 0) and
    (.correlationId | type == "string" and length > 0) and
    (.iteration | type == "number" and floor == . and . >= 0) and
    (.contractHash | type == "string" and test("^[0-9a-fA-F]{64}$"))
  ' "$TRACE_STATE_FILE" >/dev/null 2>&1 || {
    printf '%s\n' 'trace: active run state is malformed' >&2
    return 1
  }
}

trace_state_value() {
  jq -r --arg key "$1" '.[$key]' "$TRACE_STATE_FILE"
}

trace_last_sequence() {
  local run_id="${1:-}"
  if [ ! -s "$TRACE_FILE" ]; then
    printf '0\n'
  elif [ -n "$run_id" ]; then
    jq -sr --arg run "$run_id" \
      '[.[] | select(.runId == $run) | .sequence] | if length == 0 then 0 else .[-1] end' \
      "$TRACE_FILE"
  else
    jq -sr 'if length == 0 then 0 else .[-1].sequence end' "$TRACE_FILE"
  fi
}

trace_authority_check() {
  local event="$1" role verdict status
  role=$(printf '%s\n' "$event" | jq -r '.role') || return 1
  status=$(printf '%s\n' "$event" | jq -r '.status') || return 1
  verdict=$(printf '%s\n' "$event" | jq -r '.verdict // ""') || return 1
  if [ "$status" = "PASS" ] || [ "$verdict" = "PASS" ]; then
    printf '%s\n' 'trace: PASS is derived from evaluator verdict, guard result, and locked hash' >&2
    return 1
  fi
}

trace_append_event() {
  local event="$1" event_id
  case "$event" in
    *$'\n'*|*$'\r'*)
      printf '%s\n' 'trace: event must occupy one physical line' >&2
      return 1
      ;;
  esac
  if [ -e "$TRACE_FILE" ] && ! trace_validate_file; then return 1; fi
  if ! printf '%s\n' "$event" | jq -e "$(trace_schema_filter) valid_event" >/dev/null 2>&1; then
    printf '%s\n' 'trace: event does not match the strict schema' >&2
    return 1
  fi
  event_id=$(printf '%s\n' "$event" | jq -r '.eventId') || return 1
  if [ -s "$TRACE_FILE" ] && jq -s -e --arg event_id "$event_id" 'any(.[]; .eventId == $event_id)' "$TRACE_FILE" >/dev/null 2>&1; then
    printf '%s\n' 'trace: eventId already exists' >&2
    return 1
  fi
  trace_authority_check "$event" || return 1
  printf '%s\n' "$event" >> "$TRACE_FILE" || return 1
}

trace_build_event() {
  local run_id="$1" sequence="$2" iteration="$3" role="$4" phase="$5" status="$6" correlation_id="$7" contract_hash="$8"
  local timestamp="$9" score="${10}" verdict="${11}" gap="${12}" task="${13}" worktree="${14}"
  local score_set=0 verdict_set=0 gap_set=0 task_set=0 worktree_set=0
  [ -n "$score" ] && score_set=1
  [ -n "$verdict" ] && verdict_set=1
  [ -n "$gap" ] && gap_set=1
  [ -n "$task" ] && task_set=1
  [ -n "$worktree" ] && worktree_set=1
  jq -cn \
    --arg runId "$run_id" \
    --arg eventId "$(trace_new_id)" \
    --argjson sequence "$sequence" \
    --arg timestamp "$timestamp" \
    --argjson iteration "$iteration" \
    --arg role "$role" \
    --arg phase "$phase" \
    --arg status "$status" \
    --arg correlationId "$correlation_id" \
    --arg contractHash "$contract_hash" \
    --arg score "$score" --argjson scoreSet "$score_set" \
    --arg verdict "$verdict" --argjson verdictSet "$verdict_set" \
    --arg gap "$gap" --argjson gapSet "$gap_set" \
    --arg task "$task" --argjson taskSet "$task_set" \
    --arg worktree "$worktree" --argjson worktreeSet "$worktree_set" \
    '{schemaVersion: 1, eventId: $eventId, runId: $runId, sequence: $sequence,
      timestamp: $timestamp, iteration: $iteration, role: $role, phase: $phase,
      status: $status, correlationId: $correlationId, contractHash: $contractHash}
      | if ($scoreSet == 1) then .score = ($score | tonumber) else . end
      | if ($verdictSet == 1) then .verdict = $verdict else . end
      | if ($gapSet == 1) then .gap = $gap else . end
      | if ($taskSet == 1) then .task = $task else . end
      | if ($worktreeSet == 1) then .worktree = $worktree else . end'
}

trace_write_state() {
  jq -cn --arg runId "$1" --arg correlationId "$2" --argjson iteration "$3" --arg contractHash "$4" \
    '{runId: $runId, correlationId: $correlationId, iteration: $iteration, contractHash: $contractHash}' \
    > "$TRACE_STATE_FILE"
}

trace_start() {
  local run_id="" correlation_id="" iteration=0 task="" worktree="" contract_hash event sequence
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_START" >&2; return 2; }; run_id="$2"; shift 2 ;;
      --correlation-id) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_START" >&2; return 2; }; correlation_id="$2"; shift 2 ;;
      --iteration) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_START" >&2; return 2; }; iteration="$2"; shift 2 ;;
      --task) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_START" >&2; return 2; }; task="$2"; shift 2 ;;
      --worktree) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_START" >&2; return 2; }; worktree="$2"; shift 2 ;;
      *) printf '%s\n' 'usage: trace start [--run-id id] [--correlation-id id] [--iteration n] [--task text] [--worktree path]' >&2; return 2 ;;
    esac
  done
  [ -n "$run_id" ] || run_id=$(trace_new_id)
  [ -n "$correlation_id" ] || correlation_id=$(trace_new_id)
  case "$iteration" in ''|*[!0-9]*) printf '%s\n' 'trace: iteration must be a non-negative integer' >&2; return 2 ;; esac
  mkdir -p .loops || return 1
  trace_lock || return 1
  if [ -e "$TRACE_STATE_FILE" ]; then
    printf '%s\n' 'trace: an active run already exists' >&2
    trace_unlock
    return 1
  fi
  if ! trace_validate_file; then trace_unlock; return 1; fi
  if ! contract_hash=$(trace_contract_hash); then trace_unlock; return 1; fi
  if ! sequence=$(trace_last_sequence "$run_id"); then trace_unlock; return 1; fi
  sequence=$((sequence + 1))
  if ! event=$(trace_build_event "$run_id" "$sequence" "$iteration" orchestrator loop STARTED "$correlation_id" "$contract_hash" "$(trace_now)" "" "" "" "$task" "$worktree"); then trace_unlock; return 1; fi
  if ! trace_append_event "$event"; then trace_unlock; return 1; fi
  if ! trace_write_state "$run_id" "$correlation_id" "$iteration" "$contract_hash"; then trace_unlock; return 1; fi
  trace_unlock
  printf '%s\n' "$event"
}

trace_emit_json() {
  local event="$1" state_run state_correlation state_iteration state_hash current_hash sequence event_sequence event_run event_correlation event_iteration event_hash
  trace_state_valid || return 1
  state_run=$(trace_state_value runId) || return 1
  state_correlation=$(trace_state_value correlationId) || return 1
  state_iteration=$(trace_state_value iteration) || return 1
  state_hash=$(trace_state_value contractHash) || return 1
  current_hash=$(trace_contract_hash) || return 1
  [ "$current_hash" = "$state_hash" ] || { printf '%s\n' 'trace: locked contract hash changed' >&2; return 1; }
  if ! printf '%s\n' "$event" | jq -e "$(trace_schema_filter) valid_event" >/dev/null 2>&1; then
    printf '%s\n' 'trace: malformed event payload' >&2
    return 1
  fi
  event_run=$(printf '%s\n' "$event" | jq -r '.runId') || return 1
  event_correlation=$(printf '%s\n' "$event" | jq -r '.correlationId') || return 1
  event_iteration=$(printf '%s\n' "$event" | jq -r '.iteration') || return 1
  event_hash=$(printf '%s\n' "$event" | jq -r '.contractHash') || return 1
  [ "$event_run" = "$state_run" ] || { printf '%s\n' 'trace: event runId does not match active run' >&2; return 1; }
  [ "$event_hash" = "$state_hash" ] || { printf '%s\n' 'trace: event contract hash does not match active run' >&2; return 1; }
  [ "$event_correlation" = "$state_correlation" ] || { printf '%s\n' 'trace: event correlationId does not match active run' >&2; return 1; }
  [ "$event_iteration" = "$state_iteration" ] || { printf '%s\n' 'trace: event iteration does not match active run' >&2; return 1; }
  sequence=$(trace_last_sequence "$state_run") || return 1
  sequence=$((sequence + 1))
  event_sequence=$(printf '%s\n' "$event" | jq -r '.sequence') || return 1
  [ "$event_sequence" = "$sequence" ] || { printf '%s\n' 'trace: explicit sequence must equal the next sequence' >&2; return 1; }
  trace_append_event "$event" || return 1
  printf '%s\n' "$event"
}

trace_emit() {
  local event run_id correlation_id iteration contract_hash sequence timestamp status state_run state_correlation state_iteration
  if [ "$#" -eq 1 ] && [[ "$1" == \{* ]]; then
    trace_lock || return 1
    if trace_emit_json "$1"; then status=0; else status=$?; fi
    trace_unlock
    return "$status"
  fi
  if [ "$#" -gt 0 ] && [ "$1" = "--json" ]; then
    [ "$#" -eq 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }
    trace_lock || return 1
    if trace_emit_json "$2"; then status=0; else status=$?; fi
    trace_unlock
    return "$status"
  fi
  local role="orchestrator" phase="" event_status="" score="" verdict="" gap="" task="" worktree=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; run_id="$2"; shift 2 ;;
      --correlation-id) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; correlation_id="$2"; shift 2 ;;
      --iteration) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; iteration="$2"; shift 2 ;;
      --role) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; role="$2"; shift 2 ;;
      --phase) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; phase="$2"; shift 2 ;;
      --status) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; event_status="$2"; shift 2 ;;
      --score) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; score="$2"; shift 2 ;;
      --verdict) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; verdict="$2"; shift 2 ;;
      --gap) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; gap="$2"; shift 2 ;;
      --task) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; task="$2"; shift 2 ;;
      --worktree) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; worktree="$2"; shift 2 ;;
      *) printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2 ;;
    esac
  done
  trace_state_valid || return 1
  [ -n "$phase" ] && [ -n "$event_status" ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }
  state_run=$(trace_state_value runId)
  state_correlation=$(trace_state_value correlationId)
  state_iteration=$(trace_state_value iteration)
  [ -z "$run_id" ] || [ "$run_id" = "$state_run" ] || { printf '%s\n' 'trace: runId does not match active run' >&2; return 1; }
  [ -z "$correlation_id" ] || [ "$correlation_id" = "$state_correlation" ] || { printf '%s\n' 'trace: correlationId does not match active run' >&2; return 1; }
  [ -z "$iteration" ] || [ "$iteration" = "$state_iteration" ] || { printf '%s\n' 'trace: iteration does not match active run' >&2; return 1; }
  [ -n "$run_id" ] || run_id="$state_run"
  [ -n "$correlation_id" ] || correlation_id="$state_correlation"
  [ -n "$iteration" ] || iteration="$state_iteration"
  contract_hash=$(trace_state_value contractHash)
  case "$iteration" in ''|*[!0-9]*) printf '%s\n' 'trace: iteration must be a non-negative integer' >&2; return 2 ;; esac
  trace_lock || return 1
  if ! trace_validate_file; then trace_unlock; return 1; fi
  sequence=$(trace_last_sequence "$run_id") || { trace_unlock; return 1; }
  sequence=$((sequence + 1))
  timestamp=$(trace_now) || { trace_unlock; return 1; }
  event=$(trace_build_event "$run_id" "$sequence" "$iteration" "$role" "$phase" "$event_status" "$correlation_id" "$contract_hash" "$timestamp" "$score" "$verdict" "$gap" "$task" "$worktree") || { trace_unlock; return 1; }
  if ! trace_append_event "$event"; then trace_unlock; return 1; fi
  trace_unlock
  printf '%s\n' "$event"
}

trace_end() {
  local verdict="" gap="" event_status="ENDED" phase="loop"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --verdict) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_END" >&2; return 2; }; verdict="$2"; shift 2 ;;
      --gap) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_END" >&2; return 2; }; gap="$2"; shift 2 ;;
      --status) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_END" >&2; return 2; }; event_status="$2"; shift 2 ;;
      --phase) [ "$#" -ge 2 ] || { printf '%s\n' "$TRACE_USAGE_END" >&2; return 2; }; phase="$2"; shift 2 ;;
      *) printf '%s\n' 'usage: trace end [--status status] [--verdict PASS|BLOCK] [--gap text]' >&2; return 2 ;;
    esac
  done
  trace_state_valid || return 1
  [ "$verdict" != "PASS" ] || {
    printf '%s\n' 'trace: PASS is derived from evaluator verdict, guard result, and locked hash' >&2
    return 1
  }
  trace_emit --phase "$phase" --status "$event_status" --verdict "$verdict" --gap "$gap" >/dev/null || return 1
  rm -f "$TRACE_STATE_FILE" || return 1
  printf '%s\n' 'trace: ended'
}

cmd_trace() {
  local subcommand="${1:-}"
  shift || true
  case "$subcommand" in
    start) [ "$#" -gt 0 ] || { printf '%s\n' "$TRACE_USAGE_START" >&2; return 2; }; trace_start "$@" ;;
    emit) [ "$#" -gt 0 ] || { printf '%s\n' "$TRACE_USAGE_EMIT" >&2; return 2; }; trace_emit "$@" ;;
    end) [ "$#" -gt 0 ] || { printf '%s\n' "$TRACE_USAGE_END" >&2; return 2; }; trace_end "$@" ;;
    validate)
      [ "$#" -eq 1 ] || { printf '%s\n' "$TRACE_USAGE_VALIDATE" >&2; return 2; }
      trace_validate_file "$1"
      ;;
    *) printf '%s\n' 'usage: trace {start|emit|end|validate}' >&2; return 2 ;;
  esac
}
