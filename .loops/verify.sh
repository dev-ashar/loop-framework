#!/usr/bin/env bash
set -euo pipefail
cd /Users/devashar/Documents/DS/workspace/loops
test -f .loops/verify.sh || { echo "verify.sh missing — contract defect, not build fail" >&2; exit 1; }

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
[ "$(wc -l < .claude/CLAUDE.md)" -le 149 ] || fail 'CLAUDE.md grew past 149 lines'
# fable is still absent from the gateway, so nothing may route to it. sol is no
# longer banned here — it is the session default and the evaluator tier.
if grep -rq 'claude-fable-5' .claude/; then fail 'a config references claude-fable-5'; fi
grep -q '### Parallel builders' .claude/skills/run-loop/SKILL.md || fail 'run-loop lost the parallel-builders section'
# The Land step must write memory, not just say "capture a lesson" at nobody.
grep -q 'loops mem note' .claude/skills/run-loop/SKILL.md || fail 'run-loop Land step no longer records memory'
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

