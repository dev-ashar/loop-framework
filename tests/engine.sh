#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"
fail=0
mock=$(mktemp -d)
state=.loops/engine
had_state=0; saved_state=
if [ -e "$state" ]; then had_state=1; saved_state=$(cat "$state"); fi
cleanup() {
  rm -rf "$mock"
  if [ "$had_state" -eq 1 ]; then mkdir -p .loops; printf '%s\n' "$saved_state" > "$state"; else rm -f "$state"; fi
}
trap cleanup EXIT
cat > "$mock/omp" <<'SH'
#!/usr/bin/env bash
printf 'argv=%q\n' "$@" > "$OMP_CAPTURE"
printf '{"type":"turn_end","status":"completed"}\n'
SH
chmod +x "$mock/omp"
mkdir -p .loops
printf omp > "$state"
PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake OMP_MODELS_TEMPLATE="$root/templates/omp/models.yml.template" bash -c '. lib/engine.sh; cmd_engine run --dry-run worker hi' | grep -q 'no-session' || fail=$((fail+1))
PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake OMP_CAPTURE="$mock/worker.capture" OMP_MODELS_TEMPLATE="$root/templates/omp/models.yml.template" bash -c '. lib/engine.sh; cmd_engine run worker hi' | grep -q completed || fail=$((fail+1))
# Worker routing remains functional and OMP rejects non-worker routes.
grep -q '^argv=--model$' "$mock/worker.capture" || fail=$((fail+1))
grep -q '^argv=haip/claude-sonnet-5-5$' "$mock/worker.capture" || fail=$((fail+1))
if PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake OMP_MODELS_TEMPLATE="$root/templates/omp/models.yml.template" bash -c '. lib/engine.sh; cmd_engine run planner hi' >/dev/null 2>&1; then fail=$((fail+1)); fi
# Native Claude execution validates the frontmatter route before launching.
cat > "$mock/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CLAUDE_CAPTURE"
printf 'native-completed\n'
SH
chmod +x "$mock/claude"
printf claude > "$state"
PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake CLAUDE_CAPTURE="$mock/native.capture" bash -c '. lib/engine.sh; cmd_engine run worker hi' | grep -q native-completed || fail=$((fail+1))
grep -q -- '--model' "$mock/native.capture" || fail=$((fail+1))
grep -q -- 'claude-sonnet-5-5' "$mock/native.capture" || fail=$((fail+1))
grep -q -- '--effort' "$mock/native.capture" || fail=$((fail+1))
grep -qx medium "$mock/native.capture" || fail=$((fail+1))
mkdir -p "$mock/agents"
cp .claude/agents/worker.md "$mock/agents/worker.md"
sed 's/model: claude-sonnet-5-5/model: unregistered-model/' "$mock/agents/worker.md" > "$mock/agents/model-bad.md"
cp "$mock/agents/model-bad.md" "$mock/agents/worker.md"
if PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake LOOPS_AGENTS_DIR="$mock/agents" bash -c '. lib/engine.sh; cmd_engine run --dry-run worker hi' >/dev/null 2>&1; then fail=$((fail+1)); fi
cp .claude/agents/worker.md "$mock/agents/worker.md"
sed 's/effort: medium/effort: high/' "$mock/agents/worker.md" > "$mock/agents/effort-bad.md"
cp "$mock/agents/effort-bad.md" "$mock/agents/worker.md"
if PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake LOOPS_AGENTS_DIR="$mock/agents" bash -c '. lib/engine.sh; cmd_engine run --dry-run worker hi' >/dev/null 2>&1; then fail=$((fail+1)); fi
# Malformed registries must reject the direct route before either dry-run or launch.
cp "$root/templates/job-profiles.json" "$mock/profiles.json"
python3 - "$mock/profiles.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['modelRegistry']['claude-sonnet-5-5']['efforts']=[]; json.dump(x,open(p,'w'))
PY
if PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake LOOPS_PROFILES_FILE="$mock/profiles.json" bash -c '. lib/engine.sh; cmd_engine run --dry-run worker hi' >/dev/null 2>&1; then fail=$((fail+1)); fi
python3 - "$mock/profiles.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['modelRegistry']['claude-sonnet-5-5']['efforts']=['max']; x['modelRegistry']['claude-sonnet-5-5']['routes']=[]; json.dump(x,open(p,'w'))
PY
if PATH="$mock:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake LOOPS_PROFILES_FILE="$mock/profiles.json" CLAUDE_CAPTURE="$mock/malformed.capture" bash -c '. lib/engine.sh; cmd_engine run worker hi' >/dev/null 2>&1; then fail=$((fail+1)); fi
[ ! -e "$mock/malformed.capture" ] || fail=$((fail+1))
[ "$fail" -eq 0 ] && echo ENGINE_OK || { echo ENGINE_FAIL; exit 1; }
