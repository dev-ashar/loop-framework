#!/usr/bin/env bash
set -euo pipefail
cd /Users/devashar/Documents/DS/workspace/loops
test -f .loops/verify.sh || { echo "verify.sh missing — contract defect, not build fail" >&2; exit 1; }

test -d .loops/pre-build-phase4
test -s .loops/pre-build-phase4/SHA256SUMS
( cd .loops/pre-build-phase4 && shasum -a 256 -c SHA256SUMS --status )
awk '/^## Output style/{p=1} p && /^## / && !/^## Output style/{exit} p' .claude/CLAUDE.md > /tmp/adhd-now.txt
diff -q .loops/pre-build-claudemd-99-130.txt /tmp/adhd-now.txt

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
make_fixture_repo() { local name="$1" repo="$fixture_root/$1" wt="$fixture_root/$1-wt"; mkdir -p "$repo"; git -C "$repo" init -q -b main; printf 'base\n' > "$repo/ok.txt"; git -C "$repo" add ok.txt; git -C "$repo" -c user.name=verify -c user.email=verify@example.test commit -q -m base; git -C "$repo" worktree add -q "$wt" -b "$name-work"; printf '%s|%s\n' "$repo" "$wt"; }
IFS='|' IFS='|' read -r repo wt < <(make_fixture_repo in-scope-committed); printf 'changed\n' > "$wt/ok.txt"; git -C "$wt" add ok.txt; git -C "$wt" -c user.name=verify -c user.email=verify@example.test commit -q -m change; bash run.sh scope-check "$wt" main ok.txt
IFS='|' read -r repo wt < <(make_fixture_repo out-scope-committed); printf bad > "$wt/bad.txt"; git -C "$wt" add bad.txt; git -C "$wt" -c user.name=verify -c user.email=verify@example.test commit -q -m bad; set +e; output=$(bash run.sh scope-check "$wt" main ok.txt); status=$?; set -e; [ "$status" -ne 0 ]; printf '%s\n' "$output" | grep -qx bad.txt
IFS='|' read -r repo wt < <(make_fixture_repo out-scope-uncommitted); printf bad > "$wt/bad.txt"; set +e; output=$(bash run.sh scope-check "$wt" main ok.txt); status=$?; set -e; [ "$status" -ne 0 ]; printf '%s\n' "$output" | grep -qx bad.txt
IFS='|' read -r repo wt < <(make_fixture_repo out-scope-untracked); printf new > "$wt/new.txt"; set +e; output=$(bash run.sh scope-check "$wt" main ok.txt); status=$?; set -e; [ "$status" -ne 0 ]; printf '%s\n' "$output" | grep -qx new.txt

! grep -q 'merge-worktrees' run.sh
grep -q 'git merge --no-ff' .claude/skills/run-loop/SKILL.md
test -s .claude/dispatch.md
for tok in explorer planner builder evaluator orchestrator gpt-5.6-luna-mantle gpt-5.6-terra-mantle opus-5 haiku sonnet; do grep -q "$tok" .claude/dispatch.md; done
grep -q dispatch.md .claude/CLAUDE.md
[ "$(wc -l < .claude/CLAUDE.md)" -le 131 ]
! grep -rq 'gpt-5.6-sol\|claude-fable-5' .claude/
grep -q '### Parallel builders' .claude/skills/run-loop/SKILL.md
echo EVALUATOR-JUDGEMENT-REQUIRED: 3 9 12
echo VERIFY_OK
