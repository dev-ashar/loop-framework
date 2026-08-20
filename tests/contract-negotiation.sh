#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
verify="$root/.loops/verify.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

baseline="$fixture/baseline"
git archive HEAD | tar -x -C "$baseline" 2>/dev/null || { mkdir -p "$baseline"; git archive HEAD | tar -x -C "$baseline"; }
mkdir -p "$baseline/.loops/evidence"
cp "$root/.loops/evidence/preexisting.patch" "$root/.loops/evidence/baseline-tests.txt" "$baseline/.loops/evidence/"
git -C "$baseline" init -q -b main
git -C "$baseline" config user.name verify
git -C "$baseline" config user.email verify@example.test
git -C "$baseline" add -A
git -C "$baseline" commit -q -m baseline
git -C "$baseline" apply --binary "$baseline/.loops/evidence/preexisting.patch"
set +e
(cd "$baseline" && bash tests/run_tests.sh > tests.out 2>&1)
baseline_rc=$?
set -e
baseline_pass=$(grep -Eo '[0-9]+/[0-9]+ passed' "$baseline/tests.out" | tail -1)
baseline_ids=$(grep -E '^\[FAIL\] criterion ' "$baseline/tests.out" | sed -E 's/^\[FAIL\] criterion ([0-9]+):.*/\1/' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
[ "$baseline_rc" -ne 0 ] && [ "$baseline_pass" = '29/37 passed' ] && [ "$baseline_ids" = '5 11 14 21 34 35 36 37' ] || { printf '%s\n' 'NEGOTIATION_BLOCKED baseline-materialization'; exit 1; }
supersession_check() {
  local candidate="$1"
  python3 - "$root/.loops/evidence/preexisting.patch" "$candidate" <<'PY'
import hashlib, sys
from pathlib import Path
patch, root = Path(sys.argv[1]).read_text(errors="replace"), Path(sys.argv[2])
contract_hash = "be054a3f9b92d966526069850d80f8f72c6be51e7b0bf713fbca6a2d1b3da1fe"
checks = [
(".claude/skills/contract/SKILL.md", "- A fresh evaluator reviews the final contract before approval.\n- Only an explicit host-conversation response approves the exact final contract hash.\n  Local records are advisory and cannot prove approval.\n- Contract changes invalidate approval and require fresh host approval."),
(".claude/skills/contract/SKILL.md", "6. **Lock.** Validate the contract with `run.sh lint .loops/contract.md`.\n   Any lint failure blocks approval. Compute the exact contract hash after evaluation.\n   Ask the host user to approve that exact final contract. Local observations are"),
(".claude/skills/run-loop/SKILL.md", "description: The autonomous loop driver — one invocation runs a task to done. Negotiates the contract (builder proposes, evaluator attacks), then loops builder→evaluator→feed-gap-back with NO per-turn human input until the evaluator returns PASS or iterations run out; contract disproof triggers renegotiation and continuation within the original goal."),
(".claude/skills/run-loop/SKILL.md", "## Host approval gate\n\nThe final contract needs fresh evaluator review and explicit host-user approval.\nThe orchestrator must present the exact contract hash and wait for the host response."),
(".claude/agents/evaluator.md", "- Return the exact active `LOOPS-ENVELOPE` as the first physical line.\n\n1. Resolve `git rev-parse --show-toplevel`, then bind grading to that root's `.loops` directory.\n   Reject a report from another repository or stale `.loops` directory.\n2. Prove the normal or default branch before accepting a revision finding.\n3. State the scope of refutation and what the evidence does not cover.\n4. Reject SQL evidence with `WHEN NOT MATCHED BY SOURCE`, source predicates, or DELETE clauses.\n5. Read `.loops/contract.md`. That — and only that — is what you grade against."),
]
for rel, new in checks:
    text=(root/rel).read_text()
    if new not in text or text.count(new) != 1: raise SystemExit("supersession "+rel)
evidence = {
    ".loops/evidence/preexisting.patch": "a1f9e7f05b891a695ef0e0ffae7f29bf4284151095157e75b29c56573fc03faf",
    ".loops/evidence/baseline-tests.txt": "f0a8fd6e5a54c1e5a07ac2dd8c3273409743309d6e659fabe8d66859d504bdca",
}
for rel, digest in evidence.items():
    path = root / rel
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest: raise SystemExit("evidence "+rel)
if hashlib.sha256((root/".loops/contract.md").read_bytes()).hexdigest() != contract_hash: raise SystemExit("supersession-contract")
print("NEGOTIATION_OK baseline-hunks-and-log")
PY
}
supersession_check "$root"
baseline_validate() {
  local candidate="$1"
  python3 - "$root/.loops/evidence/preexisting.patch" "$baseline" "$candidate" <<'PY'
import re, sys
from pathlib import Path
patch, baseline, candidate = (Path(x) for x in sys.argv[1:])
paths = re.findall(r'^diff --git a/(.*?) b/.*$', patch.read_text(), re.M)
if not paths:
    raise SystemExit('baseline-paths-empty')
for rel in paths:
    base = baseline / rel
    current = candidate / rel
    if not base.is_file() or not current.is_file():
        raise SystemExit(f'baseline-path-missing {rel}')
    if rel == 'README.md' and base.read_bytes() != current.read_bytes():
        raise SystemExit(f'protected-byte-drift {rel}')
    if rel == '.loops/log.md' and not current.read_bytes().startswith(base.read_bytes()):
        raise SystemExit('log-prefix-drift')
print('NEGOTIATION_OK baseline-paths-and-bytes')
PY
  [ $? -eq 0 ] || return 1
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    supersession_check "$candidate" >/dev/null || return 1
done < <(python3 - "$root/.loops/evidence/preexisting.patch" <<'PY'
import re, sys
from pathlib import Path
for rel in re.findall(r'^diff --git a/(.*?) b/.*$', Path(sys.argv[1]).read_text(), re.M):
    print(rel)
PY
)
}
baseline_validate "$root" || { printf '%s\n' 'NEGOTIATION_BLOCKED baseline-validation'; exit 1; }
missing_path="$fixture/missing-baseline-path"
cp -R "$root" "$missing_path"
missing_rel=$(python3 - "$root/.loops/evidence/preexisting.patch" <<'PY'
import re, sys
from pathlib import Path
for rel in re.findall(r'^diff --git a/(.*?) b/.*$', Path(sys.argv[1]).read_text(), re.M):
    if rel != 'README.md':
        print(rel)
        break
PY
)
rm -f "$missing_path/$missing_rel"
if baseline_validate "$missing_path" >"$fixture/missing-path.out" 2>&1; then
  printf '%s\n' 'NEGOTIATION_BLOCKED missing-baseline-path'
  exit 1
fi
: # The shared baseline checker rejected the omitted path.
printf '%s\n' 'NEGOTIATION_OK baseline-missing-path-negative-fixture'
make_supersession_fixture() {
  local name="$1"
  mkdir -p "$fixture/$name/.claude/skills/contract" "$fixture/$name/.claude/skills/run-loop" "$fixture/$name/.claude/agents" "$fixture/$name/.loops/evidence"
  cp "$root/.claude/skills/contract/SKILL.md" "$fixture/$name/.claude/skills/contract/SKILL.md"
  cp "$root/.claude/skills/run-loop/SKILL.md" "$fixture/$name/.claude/skills/run-loop/SKILL.md"
  cp "$root/.claude/agents/evaluator.md" "$fixture/$name/.claude/agents/evaluator.md"
  cp "$root/.loops/contract.md" "$fixture/$name/.loops/contract.md"
  cp "$root/.loops/evidence/"* "$fixture/$name/.loops/evidence/"
}
make_supersession_fixture evaluator-arbitrary
printf '%s\n' 'arbitrary evaluator mutation' > "$fixture/evaluator-arbitrary/.claude/agents/evaluator.md"
if supersession_check "$fixture/evaluator-arbitrary" 2>"$fixture/evaluator.err"; then exit 1; fi
grep -Fq 'supersession .claude/agents/evaluator.md' "$fixture/evaluator.err" || exit 1
printf '%s\n' 'NEGOTIATION_OK evaluator-integrity-negative-fixture'
make_supersession_fixture() {
  local name="$1"
  mkdir -p "$fixture/$name/.claude/skills/contract" "$fixture/$name/.claude/skills/run-loop" "$fixture/$name/.loops/evidence"
  cp "$root/.claude/skills/contract/SKILL.md" "$fixture/$name/.claude/skills/contract/SKILL.md"
  cp "$root/.claude/skills/run-loop/SKILL.md" "$fixture/$name/.claude/skills/run-loop/SKILL.md"
  cp "$root/.loops/contract.md" "$fixture/$name/.loops/contract.md"
  cp "$root/.loops/evidence/"* "$fixture/$name/.loops/evidence/"
}
make_supersession_fixture deleted-hunk
python3 - "$fixture/deleted-hunk/.claude/skills/contract/SKILL.md" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1]); p.write_text(p.read_text().replace('- A fresh evaluator reviews the final contract before approval.\n', ''))
PY
if supersession_check "$fixture/deleted-hunk" 2>"$fixture/deleted.err"; then exit 1; fi
grep -Fq 'supersession .claude/skills/contract/SKILL.md' "$fixture/deleted.err" || exit 1
make_supersession_fixture wrong-replacement
python3 - "$fixture/wrong-replacement/.claude/skills/contract/SKILL.md" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1]); p.write_text(p.read_text().replace('explicit host-conversation response', 'wrong replacement'))
PY
if supersession_check "$fixture/wrong-replacement" 2>"$fixture/wrong.err"; then exit 1; fi
grep -Fq 'supersession .claude/skills/contract/SKILL.md' "$fixture/wrong.err" || exit 1
make_supersession_fixture wildcard-path-only
python3 - "$fixture/wildcard-path-only/.claude/skills/contract/SKILL.md" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1]); p.write_text('path-only wildcard exemption\n')
PY
if supersession_check "$fixture/wildcard-path-only" 2>"$fixture/wildcard.err"; then exit 1; fi
grep -Fq 'supersession .claude/skills/contract/SKILL.md' "$fixture/wildcard.err" || exit 1
printf '%s\n' 'NEGOTIATION_OK supersession-negative-fixtures'
negative="$fixture/claude-missing-hunk.md"
cp "$root/.claude/CLAUDE.md" "$negative"
python3 - "$negative" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text()
needle='Renegotiate and continue within the original goal when the contract is wrong.'
p.write_text(text.replace(needle, ''))
if needle in p.read_text():
    raise SystemExit('negative fixture did not remove known hunk')
print('NEGOTIATION_OK baseline-negative-fixture')
PY
printf '%s\n' 'NEGOTIATION_OK baseline-materialization'

make_report() {
  local path="$1" scope="$2" verify_line="$3"
  {
    printf '%s\n' 'BUILT:' '  files: target' '  changes: changed target' '  invariants:'
    printf '%s\n' '    - criterion one: PASS — checked'
    printf '  within-plan: %s\n' "$scope"
    printf '  verify: %s\n' "$verify_line"
    printf '%s\n' '  follow-ups: none'
  } > "$path"
}

valid="$fixture/valid"
make_report "$valid" 'yes — target only' 'bash .loops/verify.sh — exit 0 — VERIFY_OK'
bash "$verify" builder-report "$valid"
grep -Fq 'bash .loops/verify.sh builder-report <file>' "$root/.claude/agents/builder.md"
grep -Fq 'separate from goal verification' "$root/.claude/agents/builder.md"
grep -Fq 'Block evaluator dispatch' "$root/.claude/dispatch.md" "$root/.claude/skills/run-loop/SKILL.md"
printf '%s\n' 'NEGOTIATION_OK validator-discovery'

malformed="$fixture/malformed"
printf '%s\n' 'BUILT:' '  files: target' '  changes: changed target' '  invariants:' '    - criterion one: PASS — checked' '  within-plan: yes — target only' > "$malformed"
if bash "$verify" builder-report "$malformed" >/dev/null 2>&1; then
  printf '%s\n' 'NEGOTIATION_BLOCKED malformed-builder-report'
  exit 1
fi
printf '%s\n' 'NEGOTIATION_BLOCKED malformed-builder-report'

failed="$fixture/failed-verification"
make_report "$failed" 'yes — target only' 'bash .loops/verify.sh — exit 1 — VERIFY_FAILED'
if bash "$verify" builder-report "$failed" >/dev/null 2>&1; then
  printf '%s\n' 'NEGOTIATION_BLOCKED failed-verification'
  exit 1
fi
printf '%s\n' 'NEGOTIATION_BLOCKED failed-verification'

scope="$fixture/scope-failure"
make_report "$scope" 'NO — out of scope' 'bash .loops/verify.sh — exit 0 — VERIFY_OK'
if bash "$verify" builder-report "$scope" >/dev/null 2>&1; then
  printf '%s\n' 'NEGOTIATION_BLOCKED scope-failure'
  exit 1
fi
printf '%s\n' 'NEGOTIATION_BLOCKED scope-failure'

protocol="$root/.claude/dispatch.md"
run_loop="$root/.claude/skills/run-loop/SKILL.md"
contract="$root/.claude/skills/contract/SKILL.md"
for phrase in 'explorer completes before any builder' 'minimal route is explorer → builder' 'written reason' 'fresh evaluator' 'tool-ceiling failure' 'Never retry unchanged'; do
  grep -Fq "$phrase" "$protocol" "$run_loop" "$contract" || {
    printf '%s\n' "NEGOTIATION_BLOCKED protocol-$phrase"
    exit 1
  }
done
for phrase in 'cheapest decisive read-only' 'object-freshness' 'candidate relations' 'latest timestamps and state' 'Reject plan-only' 'method or route' 'explorer-only' 'moving bottleneck' 'one explorer' 'direct source checks' 'one attempt' 'no source query'; do
  grep -Fqi "$phrase" "$run_loop" "$contract" || {
    printf '%s\n' "NEGOTIATION_BLOCKED evidence-$phrase"
    exit 1
  }
done
printf '%s\n' 'NEGOTIATION_OK protocol-evidence'

if grep -Eq 'run\.sh dispatch|dispatch\.state' "$protocol" "$run_loop" "$contract"; then
  printf '%s\n' 'NEGOTIATION_BLOCKED fake-dispatch-api'
  exit 1
fi
printf '%s\n' 'NEGOTIATION_OK honest-protocol'

# Structured trace fixtures test observed evidence only. They do not enforce Agent dispatch.
trace_fixture="$fixture/observed-trace.jsonl"
cat > "$trace_fixture" <<'EOF'
{"role":"explorer","phase":"complete","tools":"Read,Grep,Glob","route":"explorer->builder","contextId":"explorer-1"}
{"role":"builder","phase":"dispatch","tools":"full","route":"explorer->builder","contextId":"builder-1"}
{"role":"evaluator","phase":"dispatch","tools":"full","route":"fresh-evaluator","contextId":"evaluator-1"}
{"role":"evaluator","phase":"dispatch","tools":"full","route":"fresh-evaluator","contextId":"evaluator-2"}
EOF
python3 - "$trace_fixture" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert any(r.get('role') == 'explorer' and r.get('phase') == 'complete' for r in rows)
assert all(r.get('tools') for r in rows)
assert len({r.get('contextId') for r in rows if r.get('role') == 'evaluator'}) == 2
print('NEGOTIATION_OK advisory-trace-valid')
PY
ceiling_fixture="$fixture/tool-ceiling-reroute.jsonl"
cat > "$ceiling_fixture" <<'EOF'
{"sequence":1,"phase":"dispatch","role":"builder","request":"inspect","tools":"Read","status":"tool-ceiling"}
{"sequence":2,"phase":"reroute","role":"general-purpose","request":"inspect","tools":"Read,Bash","changed":true,"status":"success"}
EOF
python3 - "$ceiling_fixture" <<'PY'
import json, sys
from pathlib import Path
rows=[json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert [r['sequence'] for r in rows] == [1, 2]
assert rows[0]['status'] == 'tool-ceiling'
assert rows[1]['changed'] is True and rows[1]['role'] != 'builder'
assert rows[1]['request'] == rows[0]['request'] and rows[1]['status'] == 'success'
print('NEGOTIATION_OK advisory-tool-ceiling-reroute')
PY
for case in missing-tools unchanged-reroute reused-evaluator; do
  cp "$trace_fixture" "$fixture/$case.jsonl"
done
python3 - "$fixture" <<'PY'
import json, sys
from pathlib import Path
root=Path(sys.argv[1])
def valid(path):
    rows=[json.loads(x) for x in path.read_text().splitlines()]
    if any(not r.get('tools') for r in rows): return False
    if any(r.get('route') == 'reroute' and r.get('changed') is not True for r in rows): return False
    ids=[r.get('contextId') for r in rows if r.get('role') == 'evaluator']
    return len(ids) == len(set(ids))
for name, mutate in {
    'missing-tools': lambda rows: rows[0].__setitem__('tools',''),
    'unchanged-reroute': lambda rows: rows.append({'route':'reroute','changed':False}),
    'reused-evaluator': lambda rows: rows.append({'role':'evaluator','contextId':'evaluator-1','tools':'full'}),
}.items():
    rows=[json.loads(x) for x in (root/(name+'.jsonl')).read_text().splitlines()]
    mutate(rows)
    (root/(name+'.jsonl')).write_text(''.join(json.dumps(r)+'\n' for r in rows))
    if valid(root/(name+'.jsonl')):
        raise SystemExit(name)
    print('NEGOTIATION_BLOCKED '+name)
PY

# Approval protocol fixtures. These checks document advisory harness limits.
for phrase in 'trivial low-risk' 'explicit host-user approval' 'approval-required' 'contract changes invalidate approval' 'repairs inside the approved contract'; do
  grep -Fqi "$phrase" "$root/.claude/CLAUDE.md" "$root/.claude/dispatch.md" "$root/.claude/skills/run-loop/SKILL.md" "$root/.claude/skills/contract/SKILL.md" || {
    printf '%s\n' "NEGOTIATION_BLOCKED approval-$phrase"
    exit 1
  }
done
if grep -Eiq 'automatic lock|autonomous evaluator approval' "$root/.claude/CLAUDE.md" "$root/.claude/skills/run-loop/SKILL.md" "$root/.claude/skills/contract/SKILL.md"; then
  printf '%s\n' 'NEGOTIATION_BLOCKED autonomous-bypass'
  exit 1
fi
printf '%s\n' 'NEGOTIATION_OK approval-gate-advisory'

# Compare current failure IDs and signatures against immutable baseline evidence.
python3 - "$root/.loops/evidence/baseline-tests.txt" "$root" <<'PY'
import re, subprocess, sys
from pathlib import Path
baseline=Path(sys.argv[1]).read_text()
expected={int(n): sig for n,sig in re.findall(r'\[FAIL\] criterion (\d+): ([^\n]+)', baseline)}
result=subprocess.run(['bash','tests/run_tests.sh'],cwd=sys.argv[2],text=True,capture_output=True)
current={int(n): sig for n,sig in re.findall(r'^\[FAIL\] criterion (\d+): ([^\n]+)', result.stdout+result.stderr,re.M)}
if not set(current) <= set(expected): raise SystemExit('new failure id')
for n,sig in current.items():
    if sig != expected[n]: raise SystemExit(f'signature drift {n}')
print('NEGOTIATION_OK baseline-failure-signatures')
PY
# Canonical envelope fixtures cover role binding, contract modes, reports, and quarantine.
envelope_fixture="$fixture/envelopes"
mkdir -p "$envelope_fixture"
task_hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
contract_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
make_envelope() {
  local path="$1" role="$2" contract="$3"
  printf 'LOOPS-ENVELOPE: {"correlationId":"corr","runId":"run","role":"%s","taskFingerprint":"%s","contractHash":%s}\nBUILT:\n  files: target\n  changes: changed target\n  invariants:\n    - criterion one: PASS — checked\n  within-plan: yes — target only\n  verify: bash .loops/verify.sh — exit 0 — VERIFY_OK\n  follow-ups: none\n' "$role" "$task_hash" "$contract" > "$path"
}
for role in explorer planner builder evaluator; do
  make_envelope "$envelope_fixture/$role" "$role" '"'$contract_hash'"'
  bash "$verify" agent-envelope "$envelope_fixture/$role" --correlation corr --run run --role "$role" --task "$task_hash" --contract "$contract_hash" || { printf '%s\n' "NEGOTIATION_BLOCKED envelope-$role"; exit 1; }
done
cp "$envelope_fixture/builder" "$envelope_fixture/b-to-a"
if bash "$verify" agent-envelope "$envelope_fixture/b-to-a" --correlation corr --run run --role explorer --task "$task_hash" --contract "$contract_hash"; then exit 1; fi
for field in correlation run role task contract; do
  cp "$envelope_fixture/builder" "$envelope_fixture/mismatch-$field"
  case "$field" in correlation) arg='bad';; run) arg='bad';; role) arg=explorer;; task) arg=$(printf '%064d' 1);; contract) arg=$(printf '%064d' 1);; esac
  if [ "$field" = contract ]; then
    sed -i '' "1s/$contract_hash/$arg/" "$envelope_fixture/mismatch-$field"
    bash "$verify" agent-envelope "$envelope_fixture/mismatch-$field" --correlation corr --run run --role builder --task "$task_hash" --contract "$contract_hash" >/dev/null 2>&1 && exit 1
  else
    bash "$verify" agent-envelope "$envelope_fixture/mismatch-$field" --correlation "${arg:-corr}" --run "${arg:-run}" --role "${arg:-builder}" --task "${arg:-$task_hash}" --contract "$contract_hash" >/dev/null 2>&1 && exit 1
  fi
done
make_envelope "$envelope_fixture/no-contract" builder null
bash "$verify" agent-envelope "$envelope_fixture/no-contract" --correlation corr --run run --role builder --task "$task_hash" --no-contract
sed 's/"contractHash":null/"contractHash":"'$contract_hash'"/' "$envelope_fixture/no-contract" > "$envelope_fixture/invented"
if bash "$verify" agent-envelope "$envelope_fixture/invented" --correlation corr --run run --role builder --task "$task_hash" --no-contract; then exit 1; fi
bash "$verify" builder-report "$envelope_fixture/builder"
sed 's/^  files: target$/ files: target/' "$envelope_fixture/builder" > "$envelope_fixture/malformed"
if bash "$verify" builder-report "$envelope_fixture/malformed"; then exit 1; fi
for agent in explorer planner builder; do
  grep -Fq 'LOOPS-ENVELOPE' "$root/.claude/agents/$agent.md" || { printf '%s\n' "NEGOTIATION_BLOCKED missing-envelope-$agent"; exit 1; }
done
# Evaluator remains protected, so its envelope requirement is checked by the baseline protocol text.
grep -Fq 'Validate `agent-envelope` before report parsing' "$root/.claude/skills/run-loop/SKILL.md" || exit 1
if grep -Eiq 'authenticate host sender|prevent UI contamination' "$root/.claude/agents" "$root/.loops/verify.sh"; then exit 1; fi
printf '%s\n' 'NEGOTIATION_OK envelope-binding-and-report-gates'

# Evidence checklist uses executable repository and revision fixtures.
active_root=$(git rev-parse --show-toplevel)
[ "$active_root" = "$root" ] || exit 1
[ -d "$active_root/.loops" ] || exit 1
stale="$fixture/stale-repo"; mkdir -p "$stale/.loops"; git -C "$stale" init -q
if (cd "$stale" && test "$(git rev-parse --show-toplevel)/.loops" != "$root/.loops"); then :; else exit 1; fi
revision="$fixture/revision"; mkdir -p "$revision"; git -C "$revision" init -q -b main; git -C "$revision" config user.name verify; git -C "$revision" config user.email verify@example.test
printf base > "$revision/file"; git -C "$revision" add file; git -C "$revision" commit -q -m base; ancestor=$(git -C "$revision" rev-parse HEAD); printf next > "$revision/file"; git -C "$revision" commit -qam next; child=$(git -C "$revision" rev-parse HEAD)
git -C "$revision" merge-base --is-ancestor "$ancestor" "$child" || exit 1
if git -C "$revision" merge-base --is-ancestor "$child" "$ancestor"; then exit 1; fi
for file in "$root/.claude/agents/explorer.md" "$root/.claude/agents/evaluator.md"; do
  grep -Fq 'default branch' "$file" || exit 1
  grep -Fq 'scope of refutation' "$file" || exit 1
  grep -Fq 'WHEN NOT MATCHED BY SOURCE' "$file" || exit 1
  grep -Fq 'source predicates' "$file" || exit 1
  grep -Fq 'DELETE clauses' "$file" || exit 1
done
printf '%s\n' 'NEGOTIATION_OK evidence-checklist'

# The loop continues after nonterminal narration and pauses only at terminal outcomes.
python3 - "$root/.claude/skills/run-loop/SKILL.md" "$root/.claude/dispatch.md" <<'PY'
import sys
from pathlib import Path
text='\n'.join(Path(p).read_text() for p in sys.argv[1:])
required = [
    'role-completion', 'do not emit a `loop-PASS`', 'repair-requested',
    'fresh `evaluator`', 'PASS', 'max', 'unavailable access',
    'unauthorized', 'original goal',
]
if any(item.lower() not in text.lower() for item in required): raise SystemExit('loop-continuation-protocol')
if 'role-completion' not in text or 'repair-requested' not in text: raise SystemExit('nonterminal-notification')
print('NEGOTIATION_OK loop-continuation-protocol')
PY

# Current repository changes must stay within approved implementation files.
python3 - "$root" <<'PY'
import subprocess, sys
from pathlib import Path
root=Path(sys.argv[1])
approved={'.claude/CLAUDE.md','.claude/dispatch.md','.claude/agents/explorer.md','.claude/agents/planner.md','.claude/agents/builder.md','.claude/agents/evaluator.md','.claude/skills/contract/SKILL.md','.claude/skills/run-loop/SKILL.md','README.md','run.sh','.loops/verify.sh','tests/run_tests.sh','tests/contract-negotiation.sh','.loops/log.md'}
for line in subprocess.check_output(['git','diff','--name-only'],cwd=root,text=True).splitlines():
    if line not in approved and not line.startswith('.loops/evidence/') and line != '.loops/contract.md':
        raise SystemExit('out-of-scope '+line)
print('NEGOTIATION_OK approved-dirty-paths')
PY
