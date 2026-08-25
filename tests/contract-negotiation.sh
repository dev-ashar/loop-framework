#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
verify="$root/.loops/verify.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
repo=$(git rev-parse --show-toplevel)
hash=$(sha256sum "$root/.loops/contract.md" | awk '{print $1}')
task=$(printf '%s' protocol-gates | sha256sum | awk '{print $1}')
builder_stub="$fixture/builder-stub"
builder_marker="$fixture/builder-dispatched"
cat > "$builder_stub" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
touch "$1"
STUB
chmod +x "$builder_stub"
run_builder() {
  local name=$1 expected=$2 diagnostic=${3:-} open_arg=${4:-}
  local output status
  rm -f "$builder_marker"
  set +e
  output=$(bash "$verify" approval-request "$fixture/$name" --run run --correlation corr --role builder --open "$open_arg" 2>&1)
  status=$?
  set -e
  if [ "$expected" = pass ]; then
    [ "$status" -eq 0 ] && printf '%s\n' "$output" | grep -qx APPROVAL_REQUEST_OK || return 1
    "$builder_stub" "$builder_marker"
    [ -f "$builder_marker" ]
  else
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -qx "$diagnostic" && [ ! -e "$builder_marker" ]
  fi
}
make_report() {
  local path=$1 rr=$2 ch=$3
  printf 'LOOPS-ENVELOPE: {"correlationId":"fixture","runId":"fixture","role":"builder","repoRoot":"%s","taskFingerprint":"%s","contractHash":"%s"}\nBUILT:\n  files: target\n  changes: changed target\n  invariants:\n    - approval-gate: PASS — checked\n  within-plan: yes — target-only\n  verify: bash — exit 0 — VERIFY_OK\n  follow-ups: none\n' "$rr" "$task" "$ch" > "$path"
}
make_approval() {
  local path=$1 body=$2
  {
    printf '%s\n' "APPROVAL: host-confirmed repoRoot=$repo contractHash=$hash runId=run correlationId=corr role=builder"
    printf '%b\n' "$body"
  } > "$fixture/$path"
}
run_approval() {
  local name=$1 expected=$2 diagnostic=$3 open_arg=${4:-}
  local output status marker="$fixture/$name.builder-marker"
  rm -f "$marker"
  [ -f "$fixture/$name" ] || return 1
  set +e
  output=$(bash "$verify" approval-request "$fixture/$name" --run run --correlation corr --role builder --open "$open_arg" 2>&1)
  status=$?
  set -e
  if [ "$expected" = pass ]; then
    [ "$status" -eq 0 ] && printf '%s\n' "$output" | grep -qx APPROVAL_REQUEST_OK && : > "$marker" && [ -f "$marker" ]
  else
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -qx "$diagnostic" && [ ! -e "$marker" ]
  fi
}
make_approval complete-readable 'Contract summary:
- goal: bind builder dispatch to the approved contract
- behavior: reject stale roots and hashes before dispatch
- verification: run negotiation and full verification commands
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder complete-readable pass ''
make_approval missing-summary 'Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder missing-summary reject missing-summary
make_approval zero-bullet 'Contract summary:
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder zero-bullet reject summary-bullet-count
make_approval six-bullets 'Contract summary:
- goal
- behavior
- verification
- extra
- extra
- extra
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder six-bullets reject summary-bullet-count
make_approval overlong-bullet 'Contract summary:
- this bullet contains more than twenty words and must be rejected by the approval parser because it exceeds the contract limit
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder overlong-bullet reject summary-bullet-length
make_approval hash-only 'Contract SHA-256: '$hash
run_builder hash-only reject missing-summary
make_approval open-empty 'OPEN:
Contract summary:
- goal: bind builder dispatch
- behavior: reject stale roots
- verification: run required checks
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder open-empty pass ''
make_approval open-question 'OPEN: unresolved question
Contract summary:
- goal: bind builder dispatch
- behavior: reject stale roots
- verification: run required checks
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder open-question reject open-question 'unresolved question'
cat > "$fixture/missing-approval" <<'EOF'
Contract summary:
- goal: bind builder dispatch
- behavior: reject stale roots
- verification: run required checks
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: PLACEHOLDER
EOF
sed -i '' "s/PLACEHOLDER/$hash/" "$fixture/missing-approval"
run_builder missing-approval reject missing-approval
contract_backup="$fixture/contract.md"
cp "$root/.loops/contract.md" "$contract_backup"
trap 'cp "$contract_backup" "$root/.loops/contract.md" 2>/dev/null || true; rm -rf "$fixture"' EXIT
printf '\n' >> "$root/.loops/contract.md"
make_approval changed-contract 'Contract summary:
- goal: bind builder dispatch
- behavior: reject stale roots
- verification: run required checks
Contract path: .loops/contract.md
Review command: git diff -- .loops/contract.md
Contract SHA-256: '$hash
run_builder changed-contract reject stale-contract-hash
cp "$contract_backup" "$root/.loops/contract.md"
make_report "$fixture/valid" "$repo" "$hash"
bash "$verify" agent-envelope "$fixture/valid" --correlation fixture --run fixture --role builder --task "$task" --contract "$hash"
make_report "$fixture/foreign" /foreign/repo "$hash"
if bash "$verify" agent-envelope "$fixture/foreign" --correlation fixture --run fixture --role builder --task "$task" --contract "$hash"; then exit 1; fi
make_report "$fixture/forged" "$repo" "$(printf '%064d' 1)"
if bash "$verify" agent-envelope "$fixture/forged" --correlation fixture --run fixture --role builder --task "$task" --contract "$hash"; then exit 1; fi
grep -Fq 'OPEN: unresolved blocks dispatch' .claude/agents/planner.md
grep -Fq 'Contract summary:' .claude/dispatch.md .claude/skills/run-loop/SKILL.md
grep -Fq 'Review command: git diff -- .loops/contract.md' .claude/dispatch.md .claude/skills/run-loop/SKILL.md
grep -Eiq 'zero-mid-run|unattended.*bypass|hash-only.*approve' .claude/CLAUDE.md && exit 1 || true
grep -Fq 'Stop before builder dispatch' .claude/CLAUDE.md
printf 'NEGOTIATION_OK\n'
