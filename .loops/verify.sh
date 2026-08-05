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
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
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
expected_models="$(curl -fsS "$ANTHROPIC_BASE_URL/v1/models" -H "x-api-key: $ANTHROPIC_AUTH_TOKEN" | jq -r '.data[].id' | sort)" || fail 'c6: live model fixture failed'
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

# Live path remains operational after the regression checks.
./run.sh models available >/dev/null || fail 'c6: live models available failed'

echo VERIFY_OK
