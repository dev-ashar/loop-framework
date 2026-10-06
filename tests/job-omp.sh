#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"
fail=0; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/omp" <<'SH'
#!/usr/bin/env bash
printf 'argv=%q\n' "$@" > "$OMP_CAPTURE"
printf 'PI_CODING_AGENT_DIR=%s\n' "${PI_CODING_AGENT_DIR:-}" >> "$OMP_CAPTURE"
printf 'OMP_MODEL_ID=%s\n' "${OMP_MODEL_ID:-}" >> "$OMP_CAPTURE"
printf '{"type":"turn_end","status":"completed"}\n'
SH
chmod +x "$tmp/omp"
PATH="$tmp:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake OMP_CAPTURE="$tmp/capture" OMP_CONFIG_DIR="$tmp/config" OMP_MODELS_TEMPLATE="$root/templates/omp/models.yml.template" OMP_PROFILES_FILE="$root/templates/job-profiles.json" bash -c '. lib/job-omp.sh; OMP_MODEL_ID=claude-sonnet-5-5 OMP_PROFILE=worker-default omp_engine_run worker prompt' _ >/dev/null || fail=$((fail+1))
cat > "$tmp/expected" <<EOF
argv=--no-session
argv=-p
argv=prompt
argv=--model
argv=haip/claude-sonnet-5-5
argv=--tools
argv=read\\,grep\\,glob\\,todo\\,bash\\,edit\\,write
argv=--effort
argv=medium
PI_CODING_AGENT_DIR=$tmp/config
OMP_MODEL_ID=claude-sonnet-5-5
EOF
diff -u "$tmp/expected" "$tmp/capture" >/dev/null || fail=$((fail+1))
[ -s templates/omp/models.yml.template ] || fail=$((fail+1))
. lib/job-omp.sh
# The adapter accepts exactly one structured terminal event and rejects prose.
printf '%s\n' '{"type":"turn_end","status":"completed"}' > "$tmp/ok.stream"
printf '%s\n' 'completed' > "$tmp/prose.stream"
omp_stream_terminal_ok "$tmp/ok.stream" || fail=$((fail+1))
omp_stream_terminal_ok "$tmp/prose.stream" && fail=$((fail+1))
# Exercise adapter dispatch with canonical context creation and exact objective.
cat > "$tmp/dag.json" <<EOF
{"schemaVersion":2,"jobs":[{"id":"omp-job","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["README.md"],"objective":"Define the bounded plan","verify":"true","lenses":["correctness"]}]}
EOF
. lib/job-framework.sh
. lib/job-executor.sh
omp_run=$(job_executor_init "$root" omp-test "$tmp/dag.json") || fail=$((fail+1))
job_context_trust_init "$tmp/dag.json" "$omp_run" "$root" || fail=$((fail+1))
ctx="$omp_run/omp-job.context.json"
job_runtime_set_worktree "$omp_run/jobs.json" omp-job "$root" || fail=$((fail+1))
job_context_trust_update "$omp_run/context-trust.json" omp-job "$root" pending || fail=$((fail+1))
job_context_create "$tmp/dag.json" omp-job omp-test dispatch "$root" "$root" "$ctx" || fail=$((fail+1))
PATH="$tmp:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake OMP_CAPTURE="$tmp/dispatch-capture" OMP_STREAM_FILE="$tmp/dispatch-stream" OMP_CONFIG_DIR="$tmp/dispatch-config" OMP_MODELS_TEMPLATE="$root/templates/omp/models.yml.template" LOOPS_JOB_ADAPTER=omp job_adapter_dispatch "$ctx" >/dev/null || fail=$((fail+1))
job_executor_release_lock
rm -rf "$root/.loops/runs/omp-test"
grep -Fq 'argv=haip/claude-sonnet-5-5' "$tmp/dispatch-capture" || fail=$((fail+1))
grep -Fq 'argv=--tools' "$tmp/dispatch-capture" || fail=$((fail+1))
grep -Fq 'edit' "$tmp/dispatch-capture" || fail=$((fail+1))
grep -Fq 'write' "$tmp/dispatch-capture" || fail=$((fail+1))
[ ! -e "$ctx" ] || fail=$((fail+1))
[ "$fail" -eq 0 ] && echo JOB_OMP_OK || { echo JOB_OMP_FAIL; exit 1; }
