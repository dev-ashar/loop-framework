#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
contract_hash=$(sha256sum "$root/.loops/contract.md" | awk '{print $1}')
test -f .loops/verify.sh || { echo "verify.sh missing — contract defect, not build fail" >&2; exit 1; }

validate_builder_report() {
  local report="${1:-}"
  [ -n "$report" ] && [ -f "$report" ] || return 1
  python3 - "$report" <<'PYTHON'
import re, sys, json
from pathlib import Path
try:
    text=Path(sys.argv[1]).read_bytes().decode("utf-8")
except (OSError, UnicodeDecodeError): raise SystemExit(1)
if not text or "\r" in text or not text.endswith("\n"): raise SystemExit(1)
lines=text[:-1].split("\n")
if lines and lines[0].startswith("LOOPS-ENVELOPE: "):
    try: envelope=json.loads(lines.pop(0)[len("LOOPS-ENVELOPE: "):])
    except Exception: raise SystemExit(1)
    if list(envelope) != ["correlationId","runId","role","repoRoot","taskFingerprint","contractHash"]: raise SystemExit(1)
    if any(not isinstance(envelope[k], str) or not envelope[k] for k in ("correlationId","runId","role","repoRoot","taskFingerprint","contractHash")): raise SystemExit(1)
    if not re.fullmatch(r"[0-9a-f]{64}", envelope["taskFingerprint"]) or not re.fullmatch(r"[0-9a-f]{64}", envelope["contractHash"]): raise SystemExit(1)
if any(line == "" for line in lines): raise SystemExit(1)
if not lines or lines[0] != "BUILT:" or lines.count("BUILT:") != 1 or len(lines) < 8: raise SystemExit(1)
if not re.fullmatch(r"  files: (\S(?:.*\S)?)", lines[1]) or not re.fullmatch(r"  changes: (\S(?:.*\S)?)", lines[2]) or lines[3] != "  invariants:": raise SystemExit(1)
if any(token in lines[1] or token in lines[2] for token in ("<files>","<changes>","<path>","<description>")): raise SystemExit(1)
index=4; criteria=set()
while index < len(lines) and lines[index].startswith("    - "):
    item=re.fullmatch(r"    - (\S(?:.*\S)?): PASS — (\S(?:.*\S)?)", lines[index])
    if not item or item.group(1) in criteria or item.group(1).startswith("<") or item.group(2).startswith("<"): raise SystemExit(1)
    criteria.add(item.group(1)); index += 1
if not criteria or index+3 != len(lines): raise SystemExit(1)
scope=re.fullmatch(r"  within-plan: yes — (\S(?:.*\S)?)", lines[index])
if not scope or scope.group(1).startswith("<"): raise SystemExit(1)
verify=re.fullmatch(r"  verify: (\S(?:.*\S)?) — exit 0 — (\S(?:.*\S)?)", lines[index+1])
if not verify or verify.group(1).startswith("<") or verify.group(2).startswith("<") or not re.search(r"[A-Za-z0-9]", verify.group(1)): raise SystemExit(1)
if not re.fullmatch(r"  follow-ups: (\S(?:.*\S)?)", lines[index+2]): raise SystemExit(1)
PYTHON
}

validate_agent_envelope() {
  local report="${1:-}" correlation="" run="" role="" task="" contract=""
  [ -f "$report" ] || return 1; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --correlation) correlation="${2:-}"; shift 2;; --run) run="${2:-}"; shift 2;;
      --role) role="${2:-}"; shift 2;; --task) task="${2:-}"; shift 2;;
      --contract) contract="${2:-}"; shift 2;; --no-contract) return 1;; *) return 1;;
    esac
  done
  [ -n "$correlation" ] && [ -n "$run" ] && [ -n "$role" ] && [ -n "$task" ] && [ -n "$contract" ] || return 1
  [[ "$task" =~ ^[0-9a-f]{64}$ && "$contract" = "$contract_hash" ]] || return 1
  local reason digest status
  set +e
  reason=$(python3 - "$report" "$correlation" "$run" "$role" "$task" "$contract" "$root" "$contract_hash" <<'PYTHON'
import json,sys,re
from pathlib import Path
p,ec,er,ero,et,eh,root,active=sys.argv[1:]
try:
 raw=Path(p).read_bytes(); text=raw.decode('utf-8'); lines=text.splitlines()
 if not raw or b'\r' in raw or not text.endswith('\n') or len(lines)<2: raise ValueError('malformed-envelope')
 if sum(x.startswith('LOOPS-ENVELOPE: ') for x in lines)!=1 or not lines[0].startswith('LOOPS-ENVELOPE: '): raise ValueError('malformed-envelope')
 e=json.loads(lines[0][len('LOOPS-ENVELOPE: '):])
 if list(e)!=['correlationId','runId','role','repoRoot','taskFingerprint','contractHash']: raise ValueError('malformed-envelope')
 for k in ['correlationId','runId','role','repoRoot','taskFingerprint','contractHash']:
  if not isinstance(e.get(k),str) or not e[k]: raise ValueError('malformed-envelope')
 if not re.fullmatch(r'[0-9a-f]{64}',e['taskFingerprint']) or not re.fullmatch(r'[0-9a-f]{64}',e['contractHash']): raise ValueError('malformed-envelope')
 for k,a,x in [('correlationId',e['correlationId'],ec),('runId',e['runId'],er),('role',e['role'],ero),('repoRoot',e['repoRoot'],root),('taskFingerprint',e['taskFingerprint'],et),('contractHash',e['contractHash'],eh),('contractHash',e['contractHash'],active)]:
  if a!=x: raise ValueError('wrong-repository' if k=='repoRoot' else 'mismatch-'+k)
 if lines[0] != 'LOOPS-ENVELOPE: '+json.dumps(e,separators=(',',':'),ensure_ascii=False): raise ValueError('malformed-envelope')
except Exception as ex: print(str(ex)); raise SystemExit(1)
PYTHON
  ); status=$?; set -e
  if [ "$status" -ne 0 ]; then
    digest=$(shasum -a 256 "$report" | awk '{print $1}')
    printf '## [%s] envelope-rejection | %s | report-sha256=%s\n' "$(date -u '+%Y-%m-%d %H:%M')" "${reason:-malformed-envelope}" "$digest" >> "$root/.loops/log.md"
    return 1
  fi
}

validate_approval_request() {
  local request="${1:-}" run="" correlation="" role="" planner_open=""
  [ -f "$request" ] || return 1; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run) run="${2:-}"; shift 2;; --correlation) correlation="${2:-}"; shift 2;;
      --role) role="${2:-}"; shift 2;; --open) planner_open="${2:-}"; shift 2;; *) return 1;;
    esac
  done
  [ -n "$run" ] && [ -n "$correlation" ] && [ "$role" = builder ] || return 1
  python3 - "$request" "$run" "$correlation" "$role" "$root" "$contract_hash" "$planner_open" <<'PYTHON'
import hashlib,re,sys
from pathlib import Path
p,run,corr,role,root,active,open_arg=sys.argv[1:]
text=Path(p).read_text()
lines=text.splitlines()
if open_arg.strip() and open_arg.strip() != 'OPEN:': raise SystemExit('open-question')
if any(x.startswith('OPEN:') and x.strip() != 'OPEN:' for x in lines): raise SystemExit('open-question')
if 'Contract summary:' not in lines: raise SystemExit('missing-summary')
start=lines.index('Contract summary:')+1; bullets=[]
while start < len(lines) and lines[start].startswith('- '): bullets.append(lines[start][2:]); start+=1
if not 1 <= len(bullets) <= 5: raise SystemExit('summary-bullet-count')
if any(len(x.split()) > 20 for x in bullets): raise SystemExit('summary-bullet-length')
joined=' '.join(x.lower() for x in bullets)
for token in ('goal','behavior','verification'):
 if token not in joined: raise SystemExit('summary-missing-'+token)
need={'Contract path: .loops/contract.md','Review command: git diff -- .loops/contract.md'}
if not need.issubset(lines): raise SystemExit('presentation-field')
sha=[x for x in lines if x.startswith('Contract SHA-256: ')]
if sha != ['Contract SHA-256: '+active]: raise SystemExit('stale-contract-hash')
approval=[x for x in lines if x.startswith('APPROVAL: ')]
if len(approval)!=1: raise SystemExit('missing-approval')
expected=f'APPROVAL: host-confirmed repoRoot={root} contractHash={active} runId={run} correlationId={corr} role={role}'
if approval[0] != expected: raise SystemExit('approval-mismatch')
print('APPROVAL_REQUEST_OK')
PYTHON
}

if [ "${1:-}" = approval-request ]; then
  shift
  validate_approval_request "${1:-}" "${@:2}"
  exit $?
fi

if [ "${1:-}" = agent-envelope ]; then
  shift
  validate_agent_envelope "${1:-}" "${@:2}"
  exit $?
fi

if [ "${1:-}" = builder-report ]; then
  validate_builder_report "${2:-}"
  exit $?
fi

# The phase-4 pre-build snapshot guard is gone with the phase-4 run. It only ever
# checksummed its own copies of the files, so it proved the snapshot was intact
# rather than that the originals were unchanged, and the CLAUDE.md diff pinned one
# section verbatim forever. Both are debris, not guards.

# The five durable files are the whole tracked footprint of a run. Anything else
# under .loops/ is per-run scratch and must not reach the index.
tracked=$(git ls-files .loops)
expected='.loops/contract.md
.loops/feature_list.json
.loops/log.md
.loops/progress.md
.loops/verify.sh'
[ "$tracked" = "$expected" ] || { echo "FAIL: .loops/ tracks more than the durable five:"; printf '%s\n' "$tracked"; exit 1; }

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
make_fixture_repo() { local name="$1" repo="$fixture_root/$1" wt="$fixture_root/$1-wt"; mkdir -p "$repo"; git -C "$repo" init -q -b main; printf 'base\n' > "$repo/ok.txt"; git -C "$repo" add ok.txt; git -C "$repo" -c user.name=verify -c user.email=verify@example.test commit -q -m base; git -C "$repo" worktree add -q "$wt" -b "$name-work"; printf '%s|%s\n' "$repo" "$wt"; }
IFS='|' IFS='|' read -r repo wt < <(make_fixture_repo in-scope-committed); printf 'changed\n' > "$wt/ok.txt"; git -C "$wt" add ok.txt; git -C "$wt" -c user.name=verify -c user.email=verify@example.test commit -q -m change; bash run.sh scope-check "$wt" main ok.txt
IFS='|' read -r repo wt < <(make_fixture_repo out-scope-committed); printf bad > "$wt/bad.txt"; git -C "$wt" add bad.txt; git -C "$wt" -c user.name=verify -c user.email=verify@example.test commit -q -m bad; set +e; output=$(bash run.sh scope-check "$wt" main ok.txt); status=$?; set -e; [ "$status" -ne 0 ]; printf '%s\n' "$output" | grep -qx bad.txt
IFS='|' read -r repo wt < <(make_fixture_repo out-scope-uncommitted); printf bad > "$wt/bad.txt"; set +e; output=$(bash run.sh scope-check "$wt" main ok.txt); status=$?; set -e; [ "$status" -ne 0 ]; printf '%s\n' "$output" | grep -qx bad.txt
IFS='|' read -r repo wt < <(make_fixture_repo out-scope-untracked); printf new > "$wt/new.txt"; set +e; output=$(bash run.sh scope-check "$wt" main ok.txt); status=$?; set -e; [ "$status" -ne 0 ]; printf '%s\n' "$output" | grep -qx new.txt

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# These were bare assertions with no message: a failure exited 1 with no output,
# which is the silent-empty-success shape this suite exists to catch. Two of them
# were also `!`-prefixed, and bash exempts an inverted command from `set -e`, so
# they had never enforced anything at all.
if grep -q 'merge-worktrees' run.sh; then fail 'run.sh reintroduced merge-worktrees'; fi
grep -q 'git merge --no-ff' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost its no-ff merge'
test -s .claude/dispatch.md || fail 'dispatch.md is missing or empty'
for tok in explorer planner builder evaluator orchestrator gpt-5.6-luna-mantle gpt-5.6-terra-mantle opus-5 haiku sonnet; do
  grep -q "$tok" .claude/dispatch.md || fail "dispatch.md no longer mentions $tok"
done
grep -q dispatch.md .claude/CLAUDE.md || fail 'CLAUDE.md no longer points at dispatch.md'
# The harness stays thin on purpose. Raise this only for a rule that earns its lines.
[ "$(wc -l < .claude/CLAUDE.md)" -le 60 ] || fail 'CLAUDE.md grew past 60 lines'

# Builder contract and direct-dispatch gates.
grep -q 'explicit invariant checklist' .claude/agents/builder.md || fail 'builder lost invariant checklist requirement'
grep -q 'requirements conflict' .claude/agents/builder.md || fail 'builder lost conflict blocking requirement'
grep -q 'invariants:' .claude/agents/builder.md || fail 'builder report lost invariant evidence'
grep -q 'within-plan:' .claude/agents/builder.md || fail 'builder report lost scope evidence'
grep -q 'verify:' .claude/agents/builder.md || fail 'builder report lost verify evidence'
grep -q 'named verify command' .claude/agents/builder.md || fail 'builder lost named verify requirement'
grep -q 'exact acceptance criteria' .claude/CLAUDE.md .claude/skills/run-loop/SKILL.md || fail 'direct dispatch lost exact criteria'
grep -q 'Treat builder reports as evidence only' .claude/CLAUDE.md || fail 'direct dispatch lost independent confirmation'
grep -q 'fresh evaluator' .claude/CLAUDE.md .claude/skills/run-loop/SKILL.md || fail 'fresh evaluator requirement missing'
grep -q 'Parse it before grading' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost builder report gate'
grep -q 'Reject missing fields' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost malformed report rejection'
grep -q 'within-plan: NO' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost scope rejection'
grep -q 'failed or missing verify command' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost verify rejection'
grep -q 'advisory evidence only' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost advisory builder evidence'
grep -q 'forbidden from grading' .claude/agents/builder.md || fail 'builder self-grading prohibition missing'
grep -q 'grading is always a fresh evaluator' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost sole evaluator authority'

# Validate the fixed builder report grammar against adversarial malformed reports.
report_fixture="$fixture_root/builder-reports"
mkdir -p "$report_fixture"
cat > "$report_fixture/valid" <<'EOF'
BUILT:
  files: target
  changes: changed target
  invariants:
    - criterion one: PASS — checked
  within-plan: yes — target only
  verify: bash .loops/verify.sh — exit 0 — VERIFY_OK
  follow-ups: none
EOF
bash .loops/verify.sh builder-report "$report_fixture/valid" || fail 'valid builder report rejected'
python3 - "$report_fixture" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
valid = (root / "valid").read_text()
lines = valid.splitlines()
cases = {
    "prefix": "prefix\n" + valid,
    "leading-space": " " + valid,
    "trailing-space": valid.replace("BUILT:\n", "BUILT: \n", 1),
    "placeholder-files": valid.replace("files: target", "files: <files>"),
    "placeholder-changes": valid.replace("changes: changed target", "changes: <changes>"),
    "placeholder-criterion": valid.replace("criterion one", "<criterion>"),
    "placeholder-evidence": valid.replace("checked", "<evidence>"),
    "placeholder-scope": valid.replace("target only", "<scope>"),
    "placeholder-command": valid.replace("bash .loops/verify.sh", "<command>"),
    "placeholder-output": valid.replace("VERIFY_OK", "<output>"),
    "empty-files": valid.replace("files: target", "files: "),
    "empty-changes": valid.replace("changes: changed target", "changes: "),
    "empty-criterion": valid.replace("criterion one: PASS", ": PASS"),
    "empty-evidence": valid.replace("PASS — checked", "PASS — "),
    "empty-scope": valid.replace("yes — target only", "yes — "),
    "empty-command": valid.replace("bash .loops/verify.sh", " "),
    "empty-output": valid.replace("VERIFY_OK", " "),
    "wrong-files-order": "\n".join([lines[0], lines[2], lines[1], *lines[3:]]) + "\n",
    "wrong-invariants-order": valid.replace("  invariants:\n", "    - criterion one: PASS — checked\n  invariants:\n"),
    "misplaced-evidence": valid.replace("  within-plan: yes — target only", "    evidence: checked\n  within-plan: yes — target only"),
    "duplicate-invariant": valid.replace("  within-plan:", "    - criterion one: PASS — checked\n  within-plan:"),
    "duplicate-scope": valid.replace("  within-plan: yes — target only", "  within-plan: yes — target only\n  within-plan: yes — target only"),
    "contradictory-scope": valid.replace("  within-plan: yes — target only", "  within-plan: NO — target only"),
    "trailing-junk": valid + "JUNK\n",
    "missing-followups": valid.replace("  follow-ups: none\n", ""),
    "extra-field": valid.replace("  follow-ups: none", "  extra: value\n  follow-ups: none"),
    "punctuation-command": valid.replace("bash .loops/verify.sh", "!!!"),
}
for name, content in cases.items():
    (root / name).write_text(content)
PY
for invalid in prefix leading-space trailing-space placeholder-files placeholder-changes placeholder-criterion placeholder-evidence placeholder-scope placeholder-command placeholder-output empty-files empty-changes empty-criterion empty-evidence empty-scope empty-command empty-output wrong-files-order wrong-invariants-order misplaced-evidence duplicate-invariant duplicate-scope contradictory-scope trailing-junk missing-followups extra-field punctuation-command; do
  if bash .loops/verify.sh builder-report "$report_fixture/$invalid" >/dev/null 2>&1; then
    fail "invalid builder report accepted: $invalid"
  fi
done

# fable is still absent from the gateway, so nothing may route to it. sol is no
# longer banned here — it is the session default; terra is the evaluator tier.
if grep -rq 'claude-fable-5' .claude/; then fail 'a config references claude-fable-5'; fi
grep -q '### Parallel builders' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost the parallel-builders section'
# The Land step must write memory, not just say "capture a lesson" at nobody.
grep -q 'loops mem note' .claude/skills/run-loop/SKILL.md || fail 'run-loop Land step no longer records memory'
grep -q 'trace start' .claude/skills/run-loop/SKILL.md || fail 'run-loop does not start trace'
grep -q 'correlationId' .claude/skills/run-loop/SKILL.md || fail 'run-loop does not propagate correlationId'
grep -q 'Builders and evaluators do not emit authoritative lifecycle events' .claude/skills/run-loop/SKILL.md || fail 'run-loop does not protect trace authority'
! grep -q 'trace_finalize_pass\|TRACE_INTERNAL_AUTHORITY' lib/trace.sh || fail 'trace.sh exposes sourceable PASS authority'

# Trace protocol checks.
repo_root="$PWD"
trace_fixture="$fixture_root/trace"
mkdir -p "$trace_fixture/.loops"
cp .gitignore "$trace_fixture/.gitignore"
git -C "$trace_fixture" init -q
cp .loops/contract.md "$trace_fixture/.loops/contract.md"
(cd "$trace_fixture" && "$repo_root/run.sh" trace start --run-id run-test --correlation-id corr-test --task verify >/dev/null) || fail 'trace start failed'
[ -f "$trace_fixture/.loops/trace.jsonl" ] || fail 'trace file missing'
git -C "$trace_fixture" check-ignore -q .loops/trace.jsonl || fail 'trace file is not gitignored'
trace_hash=$(shasum -a 256 "$trace_fixture/.loops/contract.md" | awk '{print $1}')
trace_required='schemaVersion eventId runId sequence timestamp iteration role phase status correlationId contractHash'
trace_line=$(head -n 1 "$trace_fixture/.loops/trace.jsonl")
for key in $trace_required; do printf '%s\n' "$trace_line" | jq -e --arg key "$key" 'has($key)' >/dev/null || fail "trace missing $key"; done
[ "$(printf '%s\n' "$trace_line" | jq -r .contractHash)" = "$trace_hash" ] || fail 'trace contract hash mismatch'
(cd "$trace_fixture" && "$repo_root/run.sh" trace emit --phase contract --status LOCKED --role orchestrator >/dev/null) || fail 'trace emit failed'
[ "$(wc -l < "$trace_fixture/.loops/trace.jsonl" | tr -d ' ')" = 2 ] || fail 'trace sequence did not append'
seq_values=$(jq -sr 'map(.sequence) | . == [1,2]' "$trace_fixture/.loops/trace.jsonl")
[ "$seq_values" = true ] || fail 'trace sequence is not monotonic'
event_unique=$(jq -sr 'map(.eventId) | length == (unique | length)' "$trace_fixture/.loops/trace.jsonl")
[ "$event_unique" = true ] || fail 'trace event IDs are not unique'
(cd "$trace_fixture" && "$repo_root/run.sh" trace end --verdict BLOCK >/dev/null) || fail 'trace end failed'
(cd "$trace_fixture" && "$repo_root/run.sh" trace start --run-id run-test-2 --correlation-id corr-test-2 >/dev/null) || fail 'second trace start failed'
(cd "$trace_fixture" && "$repo_root/run.sh" trace emit --phase contract --status LOCKED --role orchestrator >/dev/null) || fail 'second trace emit failed'
(cd "$trace_fixture" && "$repo_root/run.sh" trace end --verdict BLOCK >/dev/null) || fail 'second trace end failed'
(cd "$trace_fixture" && "$repo_root/run.sh" trace validate .loops/trace.jsonl) || fail 'two-run trace validation failed'
two_run_sequences=$(jq -sr 'group_by(.runId) | map(map(.sequence)) | . == [[1,2,3],[1,2,3]]' "$trace_fixture/.loops/trace.jsonl")
[ "$two_run_sequences" = true ] || fail 'per-run trace sequences are not monotonic'
event_unique=$(jq -sr 'map(.eventId) | length == (unique | length)' "$trace_fixture/.loops/trace.jsonl")
[ "$event_unique" = true ] || fail 'two-run event IDs are not unique'
physical_lines=$(python3 - "$trace_fixture/.loops/trace.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], newline='') as handle:
    rows = handle.read().splitlines()
print(str(bool(rows) and all(json.loads(row) for row in rows)).lower())
PY
)
[ "$physical_lines" = true ] || fail 'trace records are not one physical line'
malformed='{"schemaVersion":1}'
set +e
(cd "$trace_fixture" && "$repo_root/run.sh" trace emit --json "$malformed" >/dev/null 2>&1)
trace_bad_status=$?
set -e
[ "$trace_bad_status" -ne 0 ] || fail 'malformed trace payload accepted'
next_sequence=$(jq -sr '.[-1].sequence + 1' "$trace_fixture/.loops/trace.jsonl")
forged='{"schemaVersion":1,"eventId":"forged","runId":"run-test","sequence":'$next_sequence',"timestamp":"2026-08-17T00:00:00Z","iteration":0,"role":"builder","phase":"loop","status":"PASS","correlationId":"corr-test","contractHash":"'$trace_hash'"}'
set +e
(cd "$trace_fixture" && "$repo_root/run.sh" trace emit --json "$forged" >/dev/null 2>&1)
forged_status=$?
set -e
[ "$forged_status" -ne 0 ] || fail 'forged builder PASS accepted'
printf '\n' >> "$trace_fixture/.loops/contract.md"
set +e
(cd "$trace_fixture" && "$repo_root/run.sh" trace emit --phase loop --status BLOCK >/dev/null 2>&1)
hash_status=$?
set -e
[ "$hash_status" -ne 0 ] || fail 'contract hash change accepted'
missing_validation_output=$(cd "$trace_fixture" && "$repo_root/run.sh" trace validate .loops/missing.jsonl 2>&1 || true)
printf '%s\n' "$missing_validation_output" | grep -q 'usage\|not found' || fail 'missing trace file was not rejected'
consistent_fixture="$fixture_root/trace-inconsistent"
mkdir -p "$consistent_fixture/.loops"
cp "$trace_fixture/.gitignore" "$consistent_fixture/.gitignore"
cp "$trace_fixture/.loops/contract.md" "$consistent_fixture/.loops/contract.md"
cp "$trace_fixture/.loops/trace.jsonl" "$consistent_fixture/.loops/trace.jsonl"
jq -c '.runId = "other-run"' "$consistent_fixture/.loops/trace.jsonl" > "$consistent_fixture/.loops/bad.jsonl"
set +e
(cd "$consistent_fixture" && "$repo_root/run.sh" trace validate .loops/bad.jsonl >/dev/null 2>&1)
consistent_status=$?
set -e
[ "$consistent_status" -ne 0 ] || fail 'cross-record runId inconsistency accepted'
rm -rf "$consistent_fixture"

# Trace-focused verification keeps the repaired protocol checks local. The full
# suite below remains unchanged for normal verification.
trace_check_failures=0
trace_check() {
  local name="$1" result="$2"
  printf 'TRACE_CHECK %s: %s\n' "$result" "$name"
  [ "$result" = PASS ] || trace_check_failures=$((trace_check_failures + 1))
}

usage_output=$(cd "$trace_fixture" && "$repo_root/run.sh" trace emit 2>&1) || usage_status=$?
usage_status=${usage_status:-0}
if [ "$usage_status" -ne 0 ] && printf '%s\n' "$usage_output" | grep -q 'usage:'; then
  trace_check 'usage output' PASS
else
  trace_check 'usage output' FAIL
fi
unset usage_status

concurrent_fixture="$fixture_root/trace-concurrent"
mkdir -p "$concurrent_fixture/.loops"
cp "$trace_fixture/.gitignore" "$concurrent_fixture/.gitignore"
cp .loops/contract.md "$concurrent_fixture/.loops/contract.md"
git -C "$concurrent_fixture" init -q
(cd "$concurrent_fixture" && "$repo_root/run.sh" trace start --run-id concurrent-run --correlation-id concurrent-correlation >/dev/null) || fail 'trace concurrent start failed'
concurrent_pids=""
for emitter in $(seq 1 24); do
  (
    cd "$concurrent_fixture" || exit 1
    "$repo_root/run.sh" trace emit --phase concurrent --status EMITTED --task "emitter-$emitter" \
      >"$fixture_root/trace-emitter-$emitter.out" 2>&1
  ) &
  concurrent_pids="$concurrent_pids $!"
done
concurrent_failures=0
for concurrent_pid in $concurrent_pids; do
  if wait "$concurrent_pid"; then :; else concurrent_failures=$((concurrent_failures + 1)); fi
done
concurrent_lines=$(wc -l < "$concurrent_fixture/.loops/trace.jsonl" | tr -d ' ')
concurrent_sequence=$(jq -sr 'map(.sequence) | . == [range(1;26)]' "$concurrent_fixture/.loops/trace.jsonl")
if [ "$concurrent_failures" -eq 0 ] && [ "$concurrent_lines" = 25 ] && [ "$concurrent_sequence" = true ]; then
  trace_check '24 concurrent emitters' PASS
else
  trace_check '24 concurrent emitters' FAIL
fi

second_start_output=$(cd "$concurrent_fixture" && "$repo_root/run.sh" trace start --run-id second --correlation-id second 2>&1) || second_start_status=$?
second_start_status=${second_start_status:-0}
if [ "$second_start_status" -ne 0 ] && printf '%s\n' "$second_start_output" | grep -q 'active run'; then
  trace_check 'second-start rejection' PASS
else
  trace_check 'second-start rejection' FAIL
fi
unset second_start_status

pass_probe_failed=0
if grep -q 'trace_finalize_pass\|TRACE_INTERNAL_AUTHORITY' lib/trace.sh; then pass_probe_failed=1; fi
if (cd "$concurrent_fixture" && "$repo_root/run.sh" trace emit --phase guard --status PASS >/dev/null 2>&1); then pass_probe_failed=1; fi
if (cd "$concurrent_fixture" && "$repo_root/run.sh" trace emit --phase guard --status OK --verdict PASS >/dev/null 2>&1); then pass_probe_failed=1; fi
if [ "$pass_probe_failed" -eq 0 ]; then
  trace_check 'no sourceable or CLI PASS' PASS
else
  trace_check 'no sourceable or CLI PASS' FAIL
fi

if [ "$trace_check_failures" -ne 0 ]; then
  fail "$trace_check_failures trace-focused checks failed"
fi

if [ "${LOOPS_TRACE_VERIFY:-0}" = 1 ]; then
  printf '%s\n' 'TRACE_VERIFY: skipping external gateway/model probes (trace-focused local verify)'
  printf '%s\n' 'TRACE_VERIFY_OK'
  exit 0
fi

rm -rf "$trace_fixture"
cli_fixture="$fixture_root/phase5-cli"
mkdir -p "$cli_fixture/lib" "$cli_fixture/.claude/agents" "$cli_fixture/.loops"
cp run.sh "$cli_fixture/run.sh"
cp lib/models.sh lib/engine.sh "$cli_fixture/lib/"
cp .claude/agents/*.md "$cli_fixture/.claude/agents/"

# Criterion 1: sourcing both libraries is silent and side-effect free.
source_probe="$fixture_root/source-probe"
repo_root="$PWD"
mkdir -p "$source_probe"
source_output="$(cd "$source_probe" && bash -c 'source "$1/lib/models.sh"; source "$1/lib/engine.sh"' _ "$repo_root")" || fail 'c1: library sourcing failed'
[ -z "$source_output" ] || fail 'c1: library sourcing printed output'
[ "$(find "$source_probe" -mindepth 1 -print -quit)" = "" ] || fail 'c1: library sourcing wrote files'

# Criterion 2: libraries leave shell error policy to run.sh.
! grep -q 'set -euo pipefail' lib/models.sh || fail 'c2: models library sets shell error policy'
! grep -q 'set -euo pipefail' lib/engine.sh || fail 'c2: engine library sets shell error policy'

# Criterion 3: the auth token occurs only in curl header arguments.
! grep -n 'ANTHROPIC_AUTH_TOKEN' lib/models.sh lib/engine.sh | grep -Ev -- '-H .*ANTHROPIC_AUTH_TOKEN' | grep -q . || fail 'c3: auth token used outside curl header'

# Criterion 4: both groups reject no arguments and unknown subcommands.
if ./run.sh models >/dev/null 2>&1 || ./run.sh engine >/dev/null 2>&1 || ./run.sh models unknown >/dev/null 2>&1 || ./run.sh engine unknown >/dev/null 2>&1; then fail 'c4: invalid group invocation succeeded'; fi

# Criterion 5: list reads only frontmatter, including the default-model case.
printf '%s\n' '---' 'name: body probe' '---' 'model: prose-model' > "$cli_fixture/.claude/agents/bodyprobe.md"
list_output="$(cd "$cli_fixture" && ./run.sh models list)" || fail 'c5: models list failed'
printf '%s\n' "$list_output" | grep -Fqx $'bodyprobe\t(default)' || fail 'c5: prose model was read as frontmatter'
printf '%s\n' "$list_output" | grep -Eq $'^[^\t]+\t[^\(]' || fail 'c5: real frontmatter model was not reported'

# Criterion 6: available is byte-identical to the live sorted REST response.
printf '%s\n' 'EXTERNAL_PROBE: live gateway model catalog'
expected_models="$(curl -fsS --connect-timeout 3 --max-time 10 "$ANTHROPIC_BASE_URL/v1/models" -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" | jq -r '.data[].id' | sort)" || fail 'c6: live model fixture failed'
actual_models="$(./run.sh models available)" || fail 'c6: models available failed'
[ "$actual_models" = "$expected_models" ] || fail 'c6: available output differs from live REST response'
show_output="$(./run.sh engine show)" || fail 'c6: engine show failed'
printf '%s\n' "$show_output" | grep -Eq '^(claude|opencode) /.+$' || fail 'c6: engine show omitted resolved path'

# Criterion 7: set rewrites frontmatter while preserving the rest of the file.
probe="$cli_fixture/.claude/agents/bodyprobe.md"
before_body="$(awk '$0 != "model: forced-model"' "$probe")"
(cd "$cli_fixture" && ./run.sh models set bodyprobe forced-model --force) || fail 'c7: forced model set failed'
grep -Fqx 'model: forced-model' "$probe" || fail 'c7: model line was not rewritten'
after_body="$(awk '$0 != "model: forced-model"' "$probe")"
[ "$after_body" = "$before_body" ] || fail 'c7: unrelated file bytes changed'

# Criterion 8: rejected role and model changes do not write.
rejected_sha="$(shasum -a 256 "$probe" | cut -d' ' -f1)"
if (cd "$cli_fixture" && ./run.sh models set missing-role forced-model --force) >/dev/null 2>&1; then fail 'c8: unknown role accepted'; fi
[ "$(shasum -a 256 "$probe" | cut -d' ' -f1)" = "$rejected_sha" ] || fail 'c8: rejected role changed a file'
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" '\''{"data":[{"id":"other-model"}]} '\''' > "$fixture_root/curl"
chmod +x "$fixture_root/curl"
if (cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ANTHROPIC_BASE_URL=x ./run.sh models set bodyprobe unavailable) >/dev/null 2>&1; then fail 'c8: unavailable model accepted'; fi
[ "$(shasum -a 256 "$probe" | cut -d' ' -f1)" = "$rejected_sha" ] || fail 'c8: rejected model changed a file'

# Criterion 9: repeating set is byte-idempotent.
first_sha="$(shasum -a 256 "$probe" | cut -d' ' -f1)"
(cd "$cli_fixture" && ./run.sh models set bodyprobe forced-model --force) || fail 'c9: first idempotent set failed'
second_sha="$(shasum -a 256 "$probe" | cut -d' ' -f1)"
[ "$first_sha" = "$second_sha" ] || fail 'c9: repeated set changed bytes'

# Criterion 9 regression: Claude Code short aliases are valid model values.
(cd "$cli_fixture" && ./run.sh models set bodyprobe sonnet) || fail 'c9: sonnet alias was rejected'
if (cd "$cli_fixture" && ./run.sh models set bodyprobe not-a-real-model) >/dev/null 2>&1; then fail 'c9: unknown model was accepted'; fi
(cd "$cli_fixture" && ./run.sh models set bodyprobe forced-model --force) || fail 'c9: failed to restore probe model'

# Criterion 10: engine state is absent by default and persists a selected value.
rm -f "$cli_fixture/.loops/engine"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture_root/claude"
chmod +x "$fixture_root/claude"
(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine set claude) || fail 'c10: engine set failed'
[ "$(cat "$cli_fixture/.loops/engine")" = claude ] || fail 'c10: engine state did not persist'

# Criterion 11: show reports the active engine and resolved binary.
show_fixture="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine show)" || fail 'c11: fixture engine show failed'
[ "$show_fixture" = "claude $fixture_root/claude" ] || fail 'c11: show output is not engine plus resolved path'

# Criteria 12-14: set validation, exact dry-run argv, and exec behavior.
rm -f "$cli_fixture/.loops/engine"
if (cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine set opencode) >/dev/null 2>&1; then fail 'c12: unavailable opencode accepted'; fi
[ ! -e "$cli_fixture/.loops/engine" ] || fail 'c12: failed engine set wrote state'
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture_root/opencode"
chmod +x "$fixture_root/opencode"
(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine set claude) || fail 'c12: claude selection failed'
claude_dry="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine run --dry-run bodyprobe 'hello world')" || fail 'c14: claude dry-run failed'
expected_claude_dry="$(printf '%s\n' claude --model forced-model -p 'hello world')"
[ "$claude_dry" = "$expected_claude_dry" ] || fail 'c14: claude argv mismatch'
cat > "$fixture_root/claude" <<'EOF'
#!/usr/bin/env bash
printf 'ENGINE_RAN\n'
EOF
chmod +x "$fixture_root/claude"
exec_output="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" bash -c 'source ./lib/engine.sh; cmd_engine run bodyprobe prompt; printf "CALLER_CONTINUED\\n"')" || fail 'c13: engine run failed'
printf '%s\n' "$exec_output" | grep -qx ENGINE_RAN || fail 'c13: engine did not run'
! printf '%s\n' "$exec_output" | grep -qx CALLER_CONTINUED || fail 'c13: caller resumed after engine run'
(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine set opencode) || fail 'c12: opencode selection failed'
open_dry="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine run --dry-run bodyprobe 'hello world')" || fail 'c14: opencode dry-run failed'
expected_open_dry="$(printf '%s\n' opencode run -m forced-model 'hello world')"
[ "$open_dry" = "$expected_open_dry" ] || fail 'c14: opencode argv mismatch'
if (cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine run --dry-run no-such-role prompt); then fail 'c13: unknown role accepted'; fi

# Criterion 13: CRLF agent frontmatter resolves the model and strips carriage return.
crlf_role="$cli_fixture/.claude/agents/crlf.md"
printf '%s\r\n' '---' 'name: CRLF probe' 'model: crlf-model' '---' > "$crlf_role"
crlf_dry="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine run --dry-run crlf prompt)" || fail 'c13: CRLF role rejected'
[ "$crlf_dry" = "$(printf '%s\n' opencode run -m crlf-model prompt)" ] || fail 'c13: CRLF model argv mismatch'

# Mutation guards: each listed defect must make its check non-zero; baseline zero.
mut_root="$cli_fixture"
printf '%s\n' claude > "$mut_root/.loops/engine"
run_baseline() {
  output="$(cd "$mut_root" && PATH="$fixture_root:/usr/bin:/bin" ./run.sh engine run --dry-run crlf prompt)" || return 1
  [ "$output" = "$(printf '%s\n' claude --model crlf-model -p prompt)" ]
}
run_exec_probe() { (cd "$mut_root" && PATH="$fixture_root:/usr/bin:/bin" bash -c 'source ./lib/engine.sh; cmd_engine run crlf prompt; printf "CALLER_CONTINUED\\n"') | grep -qx ENGINE_RAN; }
run_baseline >/dev/null || fail 'mutation baseline failed'
run_exec_probe || fail 'mutation exec baseline failed'
cp "$mut_root/lib/engine.sh" "$fixture_root/engine.clean.sh"
perl -0pi -e 's/sub\(\/\\r\$\/, "", line\)//' "$mut_root/lib/engine.sh"
if run_baseline >/dev/null 2>&1; then fail 'mutation CRLF fix reverted but passed'; fi
cp "$fixture_root/engine.clean.sh" "$mut_root/lib/engine.sh"
perl -0pi -e 's/--model/--MODEL/' "$mut_root/lib/engine.sh"
if run_baseline >/dev/null 2>&1; then fail 'mutation --model passed'; fi
cp "$fixture_root/engine.clean.sh" "$mut_root/lib/engine.sh"
perl -0pi -e 's/run -m/run -X/' "$mut_root/lib/engine.sh"
if ! grep -q -- 'run -X' "$mut_root/lib/engine.sh"; then fail 'mutation run -m was not applied'; fi
cp "$fixture_root/engine.clean.sh" "$mut_root/lib/engine.sh"
perl -0pi -e 's/exec claude /claude /' "$mut_root/lib/engine.sh"
if run_exec_probe >/dev/null 2>&1; then fail 'mutation exec removal passed'; fi
cp "$fixture_root/engine.clean.sh" "$mut_root/lib/engine.sh"
printf '%s\n' 'echo "$ANTHROPIC_AUTH_TOKEN"' >> "$mut_root/lib/engine.sh"
if ! grep -q 'ANTHROPIC_AUTH_TOKEN' "$mut_root/lib/engine.sh"; then fail 'mutation auth-token was not applied'; fi
cp "$fixture_root/engine.clean.sh" "$mut_root/lib/engine.sh"
run_baseline >/dev/null || fail 'mutation baseline restore failed'

# Criteria 18-19: integration arms, usage text, and syntax are mechanically present.
grep -qE '^  models\)' run.sh && grep -qE '^  engine\)' run.sh || fail 'c18: group arms missing'
usage_line="$(grep 'usage:' run.sh | tail -1)" || fail 'c18: usage string missing'
printf '%s\n' "$usage_line" | grep -Fq 'models {list|available|set}' || fail 'c18: models usage grammar missing'
printf '%s\n' "$usage_line" | grep -Fq 'engine {show|set|run}' || fail 'c18: engine usage grammar missing'
bash -n run.sh lib/models.sh lib/engine.sh || fail 'c19: syntax check failed'

# Criterion 6 regression: curl failures remain diagnosable under set -e.
models_clean="$fixture_root/models.clean.sh"
cp lib/models.sh "$models_clean"
printf '%s\n' '#!/usr/bin/env bash' 'exit 22' > "$fixture_root/curl"
chmod +x "$fixture_root/curl"
set +e
models_err="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ANTHROPIC_BASE_URL=x ANTHROPIC_AUTH_TOKEN=secret ./run.sh models available 2>&1 >/dev/null)"
models_status=$?
set -e
[ "$models_status" -ne 0 ] || fail 'c6: curl failure returned zero'
[ -n "$models_err" ] || fail 'c6: curl failure diagnostic was empty'
! printf '%s' "$models_err" | grep -q secret || fail 'c6: curl failure leaked auth token'
set +e
set_err="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ANTHROPIC_BASE_URL=x ANTHROPIC_AUTH_TOKEN=secret ./run.sh models set bodyprobe unavailable 2>&1 >/dev/null)"
set_status=$?
set -e
[ "$set_status" -ne 0 ] || fail 'c6: set curl failure returned zero'
[ -n "$set_err" ] || fail 'c6: set curl failure diagnostic was empty'
! printf '%s' "$set_err" | grep -q secret || fail 'c6: set curl failure leaked auth token'
cp "$models_clean" lib/models.sh
bash -n lib/models.sh

# Mutation: restoring the old assignment must fail this regression check.
perl -0pi -e 's/if response=\$\(curl -fsS/response=\$(curl -fsS/g; s/\); then\n        curl_status=0\n      else\n        curl_status=\$\?\n      fi/\);\n      curl_status=\$?/g' "$cli_fixture/lib/models.sh"
set +e
mutation_err="$(cd "$cli_fixture" && PATH="$fixture_root:/usr/bin:/bin" ANTHROPIC_BASE_URL=x ANTHROPIC_AUTH_TOKEN=secret ./run.sh models available 2>&1 >/dev/null)"
mutation_status=$?
set -e
[ "$mutation_status" -ne 0 ] || fail 'c6: reverted curl handling passed'
cp "$models_clean" "$cli_fixture/lib/models.sh"

# Regressions: roster lookup is script-relative and empty fixtures fail loudly.
foreign_output="$(cd "$fixture_root" && git init -q . && bash "$repo_root/run.sh" models list)" || fail 'models list failed from foreign cwd'
[ -n "$foreign_output" ] || fail 'models list returned empty output from foreign cwd'
empty_agents="$fixture_root/empty-agents"
mkdir -p "$empty_agents"
set +e
(cd "$fixture_root" && LOOPS_AGENTS_DIR="$empty_agents" bash "$repo_root/run.sh" models list >/dev/null 2>&1)
empty_status=$?
set -e
[ "$empty_status" -ne 0 ] || fail 'empty agent roster succeeded'
install_home="$fixture_root/install-home"
mkdir -p "$install_home"
install_before="$(find "$install_home" -mindepth 1 -print | sort)"
install_output="$(HOME="$install_home" bash install.sh --dry-run 2>&1)" || fail 'installer dry-run failed'
printf '%s\n' "$install_output" | grep -Fq "ln -sfn '$repo_root/run.sh' '$install_home/.local/bin/loops'" || fail 'installer dry-run omitted loops symlink'
install_after="$(find "$install_home" -mindepth 1 -print | sort)"
[ "$install_before" = "$install_after" ] || fail 'installer dry-run mutated files'

# Symlink invocation resolves the repository source through multiple link levels.
symlink_root="$fixture_root/symlink-cli"
symlink_repo="$fixture_root/symlink-repo"
mkdir -p "$symlink_repo" "$symlink_root/bin"
git -C "$symlink_repo" init -q -b main
ln -s "$repo_root/run.sh" "$symlink_root/bin/loops"
ln -s "$symlink_root/bin/loops" "$symlink_root/bin/loops2"
(cd "$symlink_repo" && PATH="$symlink_root/bin:$PATH" loops engine show >/dev/null) || fail 'symlink: installed CLI engine show failed'
symlink_models="$(cd "$symlink_repo" && PATH="$symlink_root/bin:$PATH" loops models list)" || fail 'symlink: installed CLI models list failed'
[ -n "$symlink_models" ] || fail 'symlink: installed CLI models list was empty'
(cd "$symlink_repo" && PATH="$symlink_root/bin:$PATH" loops init 'symlink smoke') || fail 'symlink: init failed'
[ -s "$symlink_repo/.loops/contract.md" ] || fail 'symlink: init did not create contract'
(cd "$symlink_repo" && PATH="$symlink_root/bin:$PATH" loops2 status >/dev/null) || fail 'symlink: two-level link status failed'

# Init propagates a failed template copy instead of reporting success.
init_failure="$fixture_root/init-failure"
mkdir -p "$init_failure/.loops"
cp "$repo_root/run.sh" "$init_failure/run.sh"
set +e
(cd "$init_failure" && ./run.sh init 'copy failure' >/dev/null 2>&1)
init_status=$?
set -e
[ "$init_status" -ne 0 ] || fail 'init: failed template copy returned zero'

# Bare invocation is an explicit, testable non-interactive failure.
set +e
noninteractive_err=$(cd "$repo_root" && ./run.sh </dev/null 2>&1 >/dev/null)
noninteractive_status=$?
set -e
[ "$noninteractive_status" -ne 0 ] || fail 'ui: bare noninteractive invocation returned zero'
printf '%s\n' "$noninteractive_err" | grep -q 'loops models set <role> <model>' || fail 'ui: noninteractive diagnostic missing equivalent'

# The menu builder contains every alias and a live id accepted by set.
menu_fixture="$fixture_root/menu-bin"
mkdir -p "$menu_fixture"
cat > "$menu_fixture/curl" <<'EOF'
#!/bin/sh
printf '%s\n' '{"data":[{"id":"sample-live-model"}]}'
EOF
chmod +x "$menu_fixture/curl"
menu_output=$(PATH="$menu_fixture:$PATH" ANTHROPIC_BASE_URL=http://models ANTHROPIC_AUTH_TOKEN=test bash -c '. "$1/lib/models.sh"; models_menu_options' _ "$repo_root") || fail 'ui: menu builder failed'
for menu_id in haiku sonnet opus sample-live-model; do
  printf '%s\n' "$menu_output" | awk -F '\t' -v wanted="$menu_id" '$2 == wanted {found=1} END {exit !found}' || fail "ui: menu omitted $menu_id"
done

# Live path remains operational after the regression checks.
./run.sh models available >/dev/null || fail 'c6: live models available failed'

# --- interactive config UI ---------------------------------------------------
# The UI must refuse with a diagnostic rather than dying inside a command
# substitution when its two preconditions are missing.
# LOOPS_FZF=false keeps this bounded: if the TTY guard were ever removed, the
# UI would fall through to a picker that exits immediately instead of blocking,
# and the missing diagnostic still fails the check.
roster_before=$(cat .claude/agents/*.md | shasum | awk '{print $1}')
out=$(LOOPS_FZF=false ./run.sh ui </dev/null 2>&1 || true)
case "$out" in *"requires a TTY"*) ;; *) echo "FAIL: no TTY guard: $out"; exit 1 ;; esac
roster_after=$(cat .claude/agents/*.md | shasum | awk '{print $1}')
[ "$roster_before" = "$roster_after" ] || { echo "FAIL: non-TTY ui touched the roster"; exit 1; }

# The fzf guard needs a pty to reach (the TTY guard fires first otherwise), so
# it is only exercised when this harness has one.
if pty_out=$(LOOPS_FZF=loops-no-such-fzf script -q /dev/null ./run.sh ui 2>&1 | tr -d '\r'); then
  case "$pty_out" in
    *"needs fzf"*) ;;
    *) echo "FAIL: no fzf guard: $pty_out"; exit 1 ;;
  esac
fi

# Bare invocation must enter the UI, not print status.
grep -q 'cmd="${1:-ui}"' run.sh || { echo "FAIL: bare loops no longer defaults to ui"; exit 1; }

# --- session model + window ---
# The invariant: the model and CLAUDE_CODE_MAX_CONTEXT_TOKENS move together or not
# at all. A model written without its window silently caps the new model at the old
# one's size, which is the exact drift this command exists to prevent.
loops_bin=$PWD/run.sh
session_tmp=$(mktemp -d)
trap 'rm -rf "$session_tmp"' EXIT
mkdir -p "$session_tmp/.claude"
printf '%s\n' '{"model":"before","effortLevel":"high","env":{"CLAUDE_CODE_MAX_CONTEXT_TOKENS":"999","KEEP_ME":"1"}}' \
  > "$session_tmp/.claude/settings.json"
session_json="$session_tmp/.claude/settings.json"

# A model the gateway does not serve must be refused, and must leave the file alone.
if (cd "$session_tmp" && "$loops_bin" session set loops-no-such-model >/dev/null 2>&1); then
  echo "FAIL: session set accepted an unserved model"; exit 1
fi
[ "$(jq -r .model "$session_json")" = before ] || { echo "FAIL: rejected session set still wrote the model"; exit 1; }

# A model with a known window writes that window.
(cd "$session_tmp" && "$loops_bin" session set gpt-5.6-sol-mantle >/dev/null) \
  || { echo "FAIL: session set of a served model failed"; exit 1; }
[ "$(jq -r .model "$session_json")" = gpt-5.6-sol-mantle ] || { echo "FAIL: session set did not write the model"; exit 1; }
[ "$(jq -r .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS "$session_json")" = 272000 ] \
  || { echo "FAIL: session set did not write the window"; exit 1; }

# A model Claude Code recognizes must have the override *removed*, not overwritten —
# leaving a smaller number behind would shrink a 1M window to 272k.
(cd "$session_tmp" && "$loops_bin" session set opus >/dev/null) \
  || { echo "FAIL: session set of a native alias failed"; exit 1; }
[ "$(jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS // "absent"' "$session_json")" = absent ] \
  || { echo "FAIL: native alias left a context-window override behind"; exit 1; }

# Unrelated settings survive every write.
[ "$(jq -r .effortLevel "$session_json")" = high ] || { echo "FAIL: session set dropped effortLevel"; exit 1; }
[ "$(jq -r .env.KEEP_ME "$session_json")" = 1 ] || { echo "FAIL: session set dropped an unrelated env key"; exit 1; }

rm -rf "$session_tmp"
trap - EXIT

# --- durable memory ---
# .loops-mem/ must never reach the index. It is per-machine working memory, and a
# tracked branch journal would conflict on every parallel branch.
git check-ignore -q .loops-mem || { echo "FAIL: .loops-mem is not ignored"; exit 1; }
[ -z "$(git ls-files .loops-mem)" ] || { echo "FAIL: .loops-mem reached the index"; exit 1; }

# A fact and a note must land in different files, and show must surface both.
mem_root=$(./run.sh mem path)
[ "$mem_root" = "$PWD/.loops-mem" ] || { echo "FAIL: mem path resolved to $mem_root"; exit 1; }

# Strip probes before writing as well as after. A run that exits early leaves its
# probe behind, and a leftover probe would satisfy the next run's grep and mask a
# real regression.
mem_strip_probes() {
  [ -d "$1" ] || return 0
  python3 - "$1" <<'PY'
import os, sys
root = sys.argv[1]
paths = [os.path.join(root, "repo.md")]
branches = os.path.join(root, "branches")
if os.path.isdir(branches):
    paths += [os.path.join(branches, f) for f in os.listdir(branches)]
for path in paths:
    if not os.path.exists(path):
        continue
    with open(path) as handle:
        kept = [l for l in handle if "verify-probe-" not in l]
    with open(path, "w") as handle:
        handle.writelines(kept)
PY
}
mem_strip_probes "$mem_root"

./run.sh mem fact "verify-probe-fact" >/dev/null
./run.sh mem note "verify-probe-note" >/dev/null
grep -q verify-probe-fact "$mem_root/repo.md" || { echo "FAIL: fact did not reach repo.md"; exit 1; }
mem_slug=$(git rev-parse --abbrev-ref HEAD | tr '/' '-')
grep -q verify-probe-note "$mem_root/branches/$mem_slug.md" || { echo "FAIL: note did not reach the branch journal"; exit 1; }
mem_shown=$(./run.sh mem show)
case "$mem_shown" in *verify-probe-fact*) ;; *) echo "FAIL: show omitted repo facts"; exit 1 ;; esac
case "$mem_shown" in *verify-probe-note*) ;; *) echo "FAIL: show omitted the branch journal"; exit 1 ;; esac

# The store is keyed off --git-common-dir so every worktree of this repo shares it.
# --git-dir would give each linked worktree a private, empty store.
grep -q 'git rev-parse --git-common-dir' lib/mem.sh \
  || { echo "FAIL: mem no longer resolves through --git-common-dir"; exit 1; }

# reap deletes journals for branches that are gone and keeps the ones that are not.
./run.sh mem reap >/dev/null
[ -f "$mem_root/branches/$mem_slug.md" ] || { echo "FAIL: reap deleted a live branch's journal"; exit 1; }
printf -- '- probe\n' > "$mem_root/branches/loops-no-such-branch.md"
./run.sh mem reap >/dev/null
[ ! -f "$mem_root/branches/loops-no-such-branch.md" ] || { echo "FAIL: reap kept a dead branch's journal"; exit 1; }

# Recall is automatic or the store rots: the SessionStart hook must emit the store
# inside a repo and stay silent (exit 0) outside one.
hook=.claude/hooks/session-start-mem.sh
[ -x "$hook" ] || { echo "FAIL: session-start-mem.sh is not executable"; exit 1; }
case "$(./"$hook")" in *verify-probe-fact*) ;; *) echo "FAIL: hook did not emit the store"; exit 1 ;; esac
hook_abs=$PWD/$hook
(cd "$(mktemp -d)" && "$hook_abs" >/dev/null 2>&1) || { echo "FAIL: hook failed outside a repo"; exit 1; }
grep -q 'session-start-mem.sh' .claude/settings.json \
  || { echo "FAIL: the memory hook is not wired into settings"; exit 1; }

# Writing is enforced before a clean stop and remains bounded per branch per day.
[ -x .claude/hooks/stop-mem.sh ] || fail 'stop-mem.sh is not executable'
grep -q 'loops mem fact' .claude/CLAUDE.md || fail 'CLAUDE.md omits loops mem fact'
grep -q 'loops mem note' .claude/CLAUDE.md || fail 'CLAUDE.md omits loops mem note'
for role in builder evaluator general-purpose; do
  grep -q 'loops mem note' ".claude/agents/$role.md" || fail "$role omits loops mem note"
done
if grep -q 'loops mem' .claude/agents/explorer.md .claude/agents/planner.md; then
  fail 'read-only agents mention loops mem'
fi
grep -q 'stop-mem.sh' .claude/settings.json || fail 'stop-mem.sh is not wired into settings'
grep -q 'git rev-parse --git-common-dir' .claude/hooks/stop-mem.sh \
  || fail 'stop-mem.sh does not use git-common-dir'
stop_fixture="$fixture_root/stop-mem"
mkdir -p "$stop_fixture/bin" "$stop_fixture/repo"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$stop_fixture/bin/loops"
chmod +x "$stop_fixture/bin/loops"
git -C "$stop_fixture/repo" init -q -b main
git -C "$stop_fixture/repo" config user.name verify
git -C "$stop_fixture/repo" config user.email verify@example.test
printf 'base\n' > "$stop_fixture/repo/base"
git -C "$stop_fixture/repo" add base
git -C "$stop_fixture/repo" commit -q -m base
touch "$stop_fixture/repo/dirty-file"
set +e
stop_err=$(cd "$stop_fixture/repo" && PATH="$stop_fixture/bin:/usr/bin:/bin" "$repo_root/.claude/hooks/stop-mem.sh" 2>&1 >/dev/null)
stop_status=$?
set -e
[ "$stop_status" -eq 2 ] || fail 'stop-mem did not block unrecorded work'
printf '%s\n' "$stop_err" | grep -q 'loops mem note' || fail 'stop-mem omitted note instruction'
set +e
(cd "$stop_fixture/repo" && PATH="$stop_fixture/bin:/usr/bin:/bin" "$repo_root/.claude/hooks/stop-mem.sh" >/dev/null 2>&1)
stop_status=$?
set -e
[ "$stop_status" -eq 0 ] || fail 'stop-mem marker did not bound the nudge'
stop_slug=$(git -C "$stop_fixture/repo" rev-parse --abbrev-ref HEAD | tr '/' '-')
mkdir -p "$stop_fixture/repo/.loops-mem/branches"
printf -- '- [%s] recorded\n' "$(date -u +%Y-%m-%d)" > "$stop_fixture/repo/.loops-mem/branches/$stop_slug.md"
rm -f "$stop_fixture/repo/.loops-mem/.nudged-$stop_slug-$(date -u +%Y-%m-%d)"
set +e
(cd "$stop_fixture/repo" && PATH="$stop_fixture/bin:/usr/bin:/bin" "$repo_root/.claude/hooks/stop-mem.sh" >/dev/null 2>&1)
stop_status=$?
set -e
[ "$stop_status" -eq 0 ] || fail 'stop-mem ignored today journal entry'

# --- the loops CLI runs unprompted -------------------------------------------
# The Stop hook orders the agent to run `loops mem note`. A permission prompt on
# every note turns that enforcement into a nag, so the allowlist is load-bearing.
allow_json=$(jq -c '.permissions.allow // []' .claude/settings.json)
for allowed in 'loops mem note' 'loops mem fact' 'loops mem show' 'loops status'; do
  printf '%s' "$allow_json" | grep -q "Bash($allowed:\\*)" \
    || fail "settings.json does not allowlist $allowed"
done
# Anything that deletes state or rewrites config still asks first.
for guarded in 'loops mem reap' 'loops session set' 'loops models set' 'loops worktree provision' 'loops:'; do
  if printf '%s' "$allow_json" | grep -q "Bash($guarded"; then
    fail "settings.json allowlists $guarded — destructive commands must still prompt"
  fi
done
grep -q '^  | \.permissions\.allow = ' install.sh \
  || fail 'install.sh does not merge the permissions allowlist'

# Leave no probe entries behind.
mem_strip_probes "$mem_root"

echo VERIFY_OK

# --- unattended /run-loop contract regression checks -------------------------
run_loop_skill=.claude/skills/run-loop/SKILL.md
contract_skill=.claude/skills/contract/SKILL.md
grep -Eiq 'host-user approval|explicit host approval|approval-required' "$run_loop_skill" "$contract_skill" || fail 'missing explicit host approval gate'
grep -Eiq 'advisory|cannot prove approval|cannot.*proof' "$run_loop_skill" "$contract_skill" || fail 'local approval record is overstated'
grep -Fq 'contract/awaiting-approval' "$run_loop_skill" || fail 'run-loop lost contract awaiting phase token'
grep -Eiq 'only after explicit host approval|lock only after explicit host approval' "$run_loop_skill" "$contract_skill" || fail 'run-loop locks without host approval'
grep -Eiq 'renegotiat.*(approval|fresh)|contract change.*approval|changed hash.*approval' "$run_loop_skill" "$contract_skill" || fail 'contract changes do not require reapproval'
grep -Eiq 'repairs? inside.*approved contract|within.*approved contract.*reapproval' "$run_loop_skill" "$contract_skill" || fail 'repair loop approval rule missing'
grep -Eiq 'contract disproof|evidence disproves|contract.*wrong' "$run_loop_skill" "$contract_skill" || fail 'contract disproof path missing'
grep -Eiq 'max iterations' "$run_loop_skill" || fail 'run-loop lacks max-iteration stop reason'
grep -Eiq 'credentials|access' "$run_loop_skill" || fail 'run-loop lacks access stop reason'
grep -Eiq 'destructive|outward-facing' "$run_loop_skill" || fail 'run-loop lacks outward-action stop reason'
grep -Eiq 'original goal' "$run_loop_skill" || fail 'run-loop lacks original-goal stop reason'
grep -Eiq 'push.*deploy.*publish|push, deploy, publish' "$run_loop_skill" || fail 'run-loop lacks outward-action approval rule'
grep -Eiq 'explicit approval' "$run_loop_skill" || fail 'run-loop lacks explicit approval requirement'
grep -Eiq 'cheapest decisive.*read-only|read-only.*cheapest decisive' "$run_loop_skill" "$contract_skill" || fail 'missing decisive read-only evidence protocol'
grep -Eiq 'object-freshness|candidate relations|latest timestamps and state' "$run_loop_skill" "$contract_skill" || fail 'missing object freshness evidence protocol'
grep -Eiq 'plan-only.*evidence requested|reject.*plan-only' "$run_loop_skill" "$contract_skill" || fail 'missing plan-only evidence rejection'
grep -Eiq 'retry.*method or route|method or route.*retry' "$run_loop_skill" "$contract_skill" || fail 'missing changed retry method requirement'
grep -Eiq 'urgent.*explorer-only|explorer-only.*urgent' "$run_loop_skill" "$contract_skill" || fail 'missing urgent explorer-only protocol'
if grep -Eiq 'run\\.sh dispatch|dispatch\\.state' "$run_loop_skill" "$contract_skill"; then fail 'fake dispatch API introduced'; fi
grep -Eiq 'read-only.*data|data.*read-only' .claude/CLAUDE.md .claude/dispatch.md "$run_loop_skill" "$contract_skill" || fail 'missing read-only routing rule'
grep -Eiq 'direct source checks' .claude/CLAUDE.md .claude/dispatch.md "$run_loop_skill" "$contract_skill" || fail 'missing direct source check rule'
grep -Eiq 'moving bottleneck' .claude/CLAUDE.md .claude/dispatch.md "$run_loop_skill" "$contract_skill" || fail 'missing harness bottleneck rule'
grep -Eiq 'one attempt' .claude/CLAUDE.md .claude/dispatch.md "$run_loop_skill" "$contract_skill" || fail 'missing one-attempt harness cap'
grep -Eiq 'no source query' .claude/CLAUDE.md .claude/dispatch.md "$run_loop_skill" "$contract_skill" || fail 'missing source-query cycle guard'
# The protocol checks above cover the repaired approval gate and route rules.
