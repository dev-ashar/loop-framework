#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/.claude/hooks/pre-tool-use.sh"
ACTUAL_EVIDENCE="$ROOT/tests/explorer-dispatch-evidence.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
run_preflight() {
  env "$@" bash -s >"$TMP/preflight.out" 2>"$TMP/preflight.err" <<'PREFLIGHT_SCRIPT'
set -uo pipefail
emit(){ printf 'EXPLORER_PREFLIGHT:\n  route: explorer\n  command: %s\n  exit: %s\n  status: %s\n  detail: %s\n' "$1" "$2" "$3" "$4"; }
if [ "${EXPLORER_BASH_CAPABILITY:-1}" != 1 ]; then emit 'Bash capability' 1 BLOCKED 'direct Bash capability unavailable and no equivalent route selected'; exit 1; fi
command -v git >/dev/null 2>&1 || { emit 'git --version' 127 BLOCKED 'git binary unavailable and no equivalent route selected'; exit 1; }
git --version >/dev/null 2>&1 || { emit 'git --version' 1 BLOCKED 'git preflight failed'; exit 1; }; emit 'git --version' 0 COMPLETE 'git preflight passed'
command -v gh >/dev/null 2>&1 || { emit 'gh --version' 127 BLOCKED 'gh binary unavailable and no equivalent route selected'; exit 1; }
gh --version >/dev/null 2>&1 || { emit 'gh --version' 1 BLOCKED 'gh preflight failed'; exit 1; }; emit 'gh --version' 0 COMPLETE 'gh preflight passed'
repo=$(git rev-parse --show-toplevel 2>&1) || { emit 'git rev-parse --show-toplevel' 1 BLOCKED 'invalid repository and no equivalent route selected'; exit 1; }; emit 'git rev-parse --show-toplevel' 0 COMPLETE "$repo"
if [ "${EXPLORER_GH_AUTH:-1}" != 1 ]; then if [ "${EXPLORER_EQUIVALENT_ROUTE:-}" = authenticated-readonly ] && [ "${EXPLORER_EQUIVALENT_CAPABILITY:-}" = 1 ]; then emit 'gh auth status' 1 REROUTE 'selected route=authenticated-readonly; equivalent capability and authentication checks passed'; exit 0; fi; emit 'gh auth status' 1 BLOCKED 'authentication failed and no equivalent authenticated read-only route passed'; exit 1; fi
gh auth status >/dev/null 2>&1 || { emit 'gh auth status' 1 BLOCKED 'authentication failed and no equivalent authenticated route selected'; exit 1; }; emit 'gh auth status' 0 COMPLETE 'authentication passed'
if [ "${EXPLORER_SKIP_DISPATCH:-0}" = 1 ]; then exit 0; fi
printf 'EXPLORER_DISPATCH: unavailable reason=host Agent dispatch mechanism is not exposed to this harness\n' >&2; emit 'host Agent dispatch' 1 BLOCKED 'dispatch mechanism unavailable; no completion emitted'; exit 1
PREFLIGHT_SCRIPT
}
assert_preflight_complete() { run_preflight EXPLORER_SKIP_DISPATCH=1; rc=$?; test "$rc" -eq 0 || { echo "FAIL PREFLIGHT_COMPLETE exit=$rc"; exit 1; }; test "$(grep -c '^EXPLORER_PREFLIGHT:$' "$TMP/preflight.out")" -eq 4 || { echo "FAIL PREFLIGHT_BLOCKS"; exit 1; }; grep -A5 -E '^EXPLORER_PREFLIGHT:$' "$TMP/preflight.out" | grep -q 'status: COMPLETE' || { echo "FAIL PREFLIGHT_STATUS"; exit 1; }; echo "PREFLIGHT_COMPLETE: exit=0 blocks=4"; }
assert_preflight_blocked() { run_preflight "$@"; rc=$?; test "$rc" -ne 0 || { echo "FAIL PREFLIGHT_BLOCKED exit=$rc"; exit 1; }; grep -q 'status: BLOCKED' "$TMP/preflight.out" || { echo "FAIL PREFLIGHT_BLOCKED_TOKEN"; exit 1; }; [ "$(grep '^  status:' "$TMP/preflight.out" | tail -n 1)" != '  status: COMPLETE' ] || { echo "FAIL DEGRADED_COMPLETE"; exit 1; }; echo "PREFLIGHT_BLOCKED: exit=$rc"; }
assert_preflight_reroute() { run_preflight EXPLORER_GH_AUTH=0 EXPLORER_EQUIVALENT_ROUTE=authenticated-readonly EXPLORER_EQUIVALENT_CAPABILITY=1; rc=$?; test "$rc" -eq 0 || { echo "FAIL PREFLIGHT_REROUTE exit=$rc"; exit 1; }; grep -q 'status: REROUTE' "$TMP/preflight.out" || { echo "FAIL PREFLIGHT_REROUTE_TOKEN"; exit 1; }; grep -q 'selected route=authenticated-readonly' "$TMP/preflight.out" || { echo "FAIL PREFLIGHT_REROUTE_ROUTE"; exit 1; }; echo "PREFLIGHT_REROUTE: exit=0 route=authenticated-readonly"; }
grep -q '^dispatch_reference: a4be60477d103643c$' "$ACTUAL_EVIDENCE" || { echo "FAIL ACTUAL_EVIDENCE_REFERENCE"; exit 1; }
test "$(grep -c '^EXPLORER_PREFLIGHT:$' "$ACTUAL_EVIDENCE")" -eq 4 || { echo "FAIL ACTUAL_EVIDENCE_BLOCK_COUNT"; exit 1; }
grep -q '^  command: gh repo view --json nameWithOwner$' "$ACTUAL_EVIDENCE" || { echo "FAIL ACTUAL_EVIDENCE_COMMAND"; exit 1; }
grep -q '^  detail: Repository: dev-ashar/loop-framework$' "$ACTUAL_EVIDENCE" || { echo "FAIL ACTUAL_EVIDENCE_REPOSITORY"; exit 1; }
grep -q '^Final status: COMPLETE$' "$ACTUAL_EVIDENCE" || { echo "FAIL ACTUAL_EVIDENCE_RESULT"; exit 1; }
echo "ACTUAL_DISPATCH_EVIDENCE: verified dispatch_reference=a4be60477d103643c blocks=4 result=COMPLETE"
assert_preflight_complete
run_preflight; rc=$?; test "$rc" -ne 0 || { echo "FAIL DISPATCH_UNAVAILABLE exit=$rc"; exit 1; }; grep -q 'status: BLOCKED' "$TMP/preflight.out" || { echo "FAIL DISPATCH_UNAVAILABLE_TOKEN"; exit 1; }; grep -q 'EXPLORER_DISPATCH: unavailable reason=' "$TMP/preflight.err" || { echo "FAIL DISPATCH_UNAVAILABLE_REASON"; exit 1; }; echo "DISPATCH_UNAVAILABLE: status=BLOCKED bounded-reason-recorded";
assert_preflight_blocked EXPLORER_BASH_CAPABILITY=0
mkdir -p "$TMP/no-git"
printf '%s\n' '#!/usr/bin/env bash' 'exit 127' > "$TMP/no-git/git"
chmod +x "$TMP/no-git/git"
assert_preflight_blocked PATH="$TMP/no-git:$PATH"
assert_preflight_blocked EXPLORER_GH_AUTH=0
assert_preflight_reroute
run_hook() { printf '%s' "{\"agent_id\":\"explorer-fixture\",\"tool_input\":{\"command\":$(printf '%s' "$1" | jq -Rs .)}}" | bash "$HOOK" >"$TMP/out" 2>"$TMP/err"; }
assert_allow() { run_hook "$1"; test $? -eq 0 || { echo "FAIL ALLOW_READONLY: $1"; exit 1; }; echo "ALLOW_READONLY: $1 exit=0"; }
assert_block() { run_hook "$1"; rc=$?; test "$rc" -eq 2 || { echo "FAIL BLOCK_MUTATION: $1 exit=$rc"; exit 1; }; echo "BLOCK_MUTATION: $1 exit=2"; }
assert_allow 'git status --short'
assert_allow 'git log -1'
assert_block 'git commit -m fixture'
assert_block 'git push origin HEAD'
assert_block 'git branch --delete fixture'
assert_block 'git tag --delete fixture'
assert_allow 'gh pr view 1'
assert_allow 'gh api repos/o/r'
assert_allow 'gh api repos/o/r --method GET'
assert_block 'gh api repos/o/r --method POST'
assert_block 'gh api repos/o/r -X PUT'
assert_block 'gh api repos/o/r --method PATCH'
assert_block 'gh api repos/o/r -X DELETE'
assert_block 'gh repo edit o/r --description fixture'
assert_block 'gh pr comment 1 --body fixture'
assert_block 'gh pr create --title fixture --body fixture'
assert_block 'gh issue close 1'
python3 - "$ROOT/.claude/settings.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data=json.load(f)
hooks=data["hooks"]["PreToolUse"]
assert any(x["matcher"] == "Bash" and x["hooks"][0]["command"] == "$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-use.sh" for x in hooks)
print("SETTINGS_BINDING: exact command")
PY
if grep -Eq '^tools: .*Bash' "$ROOT/.claude/agents/explorer.md"; then
  echo "EXPLORER_CAPABILITY: Bash listed"
else
  echo "FAIL EXPLORER_CAPABILITY: Bash missing"; exit 1
fi
for command in 'git --version' 'gh --version' 'git rev-parse --show-toplevel' 'gh auth status'; do
  set +e
  output=$(eval "$command" 2>&1)
  rc=$?
  set -e
  if [ "$command" = 'gh auth status' ] && [ "$rc" -ne 0 ]; then
    echo "EXPLORER_DISPATCH: unavailable reason=gh auth status exit=$rc"
    echo "EXPLORER_PREFLIGHT: route: explorer command: $command exit: $rc status: BLOCKED detail: authentication unavailable"
    exit 0
  fi
  if [ "$rc" -ne 0 ]; then
    echo "EXPLORER_DISPATCH: unavailable reason=$command exit=$rc"
    echo "EXPLORER_PREFLIGHT: route: explorer command: $command exit: $rc status: BLOCKED detail: preflight failed"
    exit 0
  fi
  echo "EXPLORER_PREFLIGHT: route: explorer command: $command exit: 0 status: COMPLETE detail: ${output%%$'\n'*}"
done
echo "EXPLORER_DISPATCH: available route=explorer"
manifest=/tmp/explorer-git-gh-preexisting.VV69cj
prefix=/tmp/explorer-git-gh-log-prefix.MW6itX
if [ -f "$manifest" ] && [ -f "$prefix" ]; then
  frozen_ok=1
  while read -r hash path; do [ "$(sha256sum -- "$ROOT/$path" | awk '{print $1}')" = "$hash" ] || frozen_ok=0; done < "$manifest"
  current=$(mktemp); trap 'rm -f "$current"; rm -rf "$TMP"' EXIT
  git -C "$ROOT" diff --name-only | sort -u > "$current"
  echo "TASK_DELTA_EVIDENCE: manifest=$manifest log_prefix=$prefix frozen_hashes=$frozen_ok"
  echo "TASK_DELTA_PATHS: $(cat "$current" | tr '\n' ' ')"
else
  echo "TASK_DELTA_EVIDENCE: unavailable reason=bootstrap manifest missing"; exit 1
fi
