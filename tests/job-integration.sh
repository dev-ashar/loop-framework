#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../lib/job-integration.sh
. "$root/lib/job-integration.sh"
fail=0
ok=0
pass(){ ok=$((ok+1)); }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
expect_token(){ local name=$1 token=$2; shift 2; local out rc; set +e; out=$("$@" 2>&1); rc=$?; set -e; if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -Fq "$token"; then pass; else bad "$name token=$token output=$out rc=$rc"; fi; }
expect_output(){ local name=$1 token=$2; shift 2; local out rc; set +e; out=$("$@" 2>&1); rc=$?; set -e; if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Fq "$token"; then pass; else bad "$name token=$token output=$out rc=$rc"; fi; }
t=$(mktemp -d)
cleanup(){ rm -rf "$t"; }
trap cleanup EXIT
r="$t/repo"; mkdir "$r"; git -C "$r" init -q; git -C "$r" config user.email test@example.invalid; git -C "$r" config user.name test
printf 'base\n' > "$r/value.txt"; git -C "$r" add value.txt; git -C "$r" commit -qm base; base=$(git -C "$r" rev-parse HEAD)
git -C "$r" checkout -qb left; printf 'left\n' > "$r/value.txt"; git -C "$r" commit -qam left
git -C "$r" checkout -qb right "$base"; printf 'right\n' > "$r/value.txt"; git -C "$r" commit -qam right
git -C "$r" checkout -q main 2>/dev/null || git -C "$r" checkout -q master
printf 'left\tleft\nright\tright\n' > "$t/records"
set +e
out=$(job_integration_run "$r" "$base" real-conflict "$t/records" "$t/conflict" 2>&1); rc=$?
set -e
[ "$rc" -eq 10 ] && printf '%s' "$out" | grep -Fq INTEGRATION_CONFLICT && pass || bad 'same-line conflict status'
[ -s "$t/conflict" ] && grep -Fq 'conflicted_path=value.txt' "$t/conflict" && pass || bad 'conflict evidence'
git -C "$r" show-ref --verify --quiet refs/heads/left && git -C "$r" show-ref --verify --quiet refs/heads/right && pass || bad 'source branches retained'
[ "$(git -C "$r" status --porcelain)" = '' ] && [ "$(git -C "$r" rev-parse HEAD)" = "$base" ] && pass || bad 'main worktree clean'
[ ! -d "$r/.loops/runs/real-conflict/integration-worktree" ] && pass || bad 'integration worktree cleanup'
expect_token downstream-gate DOWNSTREAM_BLOCKED job_integration_gate_downstream conflicted
# A local artifact cannot create approval, and test provenance cannot pass production.
fixture_callback(){ printf 'host-control-plane\t%s\t%s\t%s\t%s\tbuilder\t2026-08-25T12:00:00Z\n' "$1" "$2" "$3" "$4"; }
job_approval_test_adapter_new test-adapter fixture_callback >/dev/null
expect_token fixture-rejected APPROVAL_OBSERVATION_INVALID job_approval_observe "$r" contract run correlation builder
approval_callback(){ printf 'host-control-plane\t%s\t%s\t%s\t%s\tbuilder\t2026-08-25T12:00:00Z\n' "$1" "$2" "$3" "$4"; }
job_approval_observer_new production approval_callback >/dev/null
expect_token stale-contract APPROVAL_OBSERVATION_INVALID job_approval_observe "$r" contract run correlation evaluator
expect_output good-observation APPROVAL_OBSERVATION_OK job_approval_observe "$r" contract run correlation builder
bad_callback(){ printf 'file\t%s\t%s\t%s\t%s\tbuilder\t2026-08-25T12:00:00Z\n' "$1" "$2" "$3" "$4"; }
job_approval_observer_new production bad_callback >/dev/null
expect_token bad-source APPROVAL_OBSERVATION_INVALID job_approval_observe "$r" contract run correlation builder
if [ "$fail" -ne 0 ]; then printf 'JOB_INTEGRATION_FAIL failures=%s passes=%s\n' "$fail" "$ok"; exit 1; fi
printf 'JOB_INTEGRATION_OK\n'
