#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"
fail=0
pass=0
ok(){ pass=$((pass+1)); }
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
expect_ok(){ local n=$1; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$n"; fi; }
expect_fail(){ local n=$1; shift; if "$@" >/dev/null 2>&1; then bad "$n accepted"; else ok; fi; }
expect_token(){ local n=$1 token=$2; shift 2; local out; out=$($@ 2>&1); local rc=$?; if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -Fq "$token"; then ok; else bad "$n token=$token output=$out"; fi; }
[ "$(bash run.sh job profiles 2>/dev/null)" = PROFILE_OK ] && ok || bad profiles

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/valid.json" <<'JSON'
{"schemaVersion":2,"jobs":[{"id":"build-a","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["lib/a.sh"],"objective":"implement requested change","verify":"true","lenses":["correctness"]},{"id":"build-b","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":["build-a"],"writeScope":["lib/b.sh"],"objective":"implement requested change","verify":"true","lenses":["scope"]},{"id":"review-a","role":"reviewer","profile":"reviewer-default","modelTier":"primary","dependsOn":["build-a"],"writeScope":[],"readScope":["lib/a.sh"],"objective":"review build a","verify":"true","lenses":["correctness"]},{"id":"review-b","role":"reviewer","profile":"reviewer-default","modelTier":"primary","dependsOn":["build-b"],"writeScope":[],"readScope":["lib/b.sh"],"objective":"review build b","verify":"true","lenses":["scope"]}]}
JSON
expect_ok valid-dag bash run.sh job validate "$t/valid.json"
[ "$(bash run.sh job schedule "$t/valid.json" 2>/dev/null)" = $'build-a\nbuild-b\nreview-a\nreview-b' ] && ok || bad schedule
[ "$(bash run.sh job route worker-default operational 2>/dev/null)" = claude-sonnet-5-5 ] && ok || bad route
[ "$(bash run.sh job route architect-default primary 2>/dev/null)" = claude-sonnet-5-5 ] && ok || bad architect-primary-route
expect_fail unknown-tier bash run.sh job route worker-default unknown

cat > "$t/profile-mismatch.json" <<'JSON'
{"schemaVersion":2,"jobs":[{"id":"review","role":"reviewer","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["x"],"objective":"review change","verify":"true","lenses":["correctness"]}]}
JSON
expect_token profile-mismatch ROUTE_INVALID bash run.sh job validate "$t/profile-mismatch.json"
cat > "$t/unknown.json" <<'JSON'
{"schemaVersion":2,"jobs":[],"extra":1}
JSON
expect_token unknown-property DAG_SCHEMA_INVALID bash run.sh job validate "$t/unknown.json"
printf '%s\n' '{"schemaVersion":2,"schemaVersion":2,"jobs":[]}' > "$t/duplicate.json"
expect_token duplicate-key DAG_DUPLICATE_KEY bash run.sh job validate "$t/duplicate.json"
for version in 0 1; do jq --argjson v "$version" '.schemaVersion=$v' "$t/valid.json" > "$t/v.json"; expect_token "version-$version" DAG_SCHEMA_INVALID bash run.sh job validate "$t/v.json"; done

cat > "$t/self.json" <<'JSON'
{"schemaVersion":2,"jobs":[{"id":"a","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":["a"],"writeScope":["x"],"objective":"review change","verify":"true","lenses":["correctness"]}]}
JSON
expect_token self-dependency DAG_SELF_DEPENDENCY bash run.sh job validate "$t/self.json"
cat > "$t/cycle.json" <<'JSON'
{"schemaVersion":2,"jobs":[{"id":"a","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":["b"],"writeScope":["x"],"objective":"cycle test" ,"verify":"true","lenses":["correctness"]},{"id":"b","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":["a"],"writeScope":["y"],"objective":"review change","verify":"true","lenses":["correctness"]}]}
JSON
expect_token cycle DAG_CYCLE bash run.sh job validate "$t/cycle.json"
for p in '../bad' '/absolute' 'a//b' 'dir/' 'a/./b' 'a/../b'; do jq --arg p "$p" '.jobs[0].writeScope=[$p]' "$t/valid.json" > "$t/path.json"; expect_fail "path-$p" bash run.sh job validate "$t/path.json"; done
jq '.jobs[1].writeScope=["lib/a.sh"]' "$t/valid.json" > "$t/overlap.json"
expect_token cross-job-overlap CROSS_JOB_SCOPE_OVERLAP bash run.sh job validate "$t/overlap.json"
jq '.jobs[0].dependsOn=["missing"]' "$t/valid.json" > "$t/missing-dep.json"
expect_fail missing-dependency bash run.sh job validate "$t/missing-dep.json"
jq '.jobs[0].lenses=["unknown"]' "$t/valid.json" > "$t/lens.json"
expect_fail unknown-lens bash run.sh job validate "$t/lens.json"
jq '.jobs[0].verify=""' "$t/valid.json" > "$t/verify.json"
expect_fail empty-verify bash run.sh job validate "$t/verify.json"
jq '.jobs[0].dependsOn=["build-a"]' "$t/valid.json" > "$t/repeat.json"
expect_fail repeated-dependency bash run.sh job validate "$t/repeat.json"

# Manifest is a strict three-column TSV with unique guard IDs.
awk -F '\t' 'NF!=3 || $1=="" || $2=="" || $3=="" {bad=1} {ids[$1]++} END{for(i in ids)if(ids[i]>1)bad=1; exit bad}' tests/job-framework-guards.tsv && ok || bad guard-manifest
for token in DAG_CYCLE CROSS_JOB_SCOPE_OVERLAP DAG_SELF_DEPENDENCY DAG_SCHEMA_INVALID DAG_DUPLICATE_KEY ROUTE_INVALID; do grep -Rqs "$token" run.sh lib templates && ok || bad "diagnostic-$token"; done

# Adapter guard is registry-driven: model in registry, role in roles, effort in efforts.
guard_tmp=$(mktemp -d); trap 'rm -rf "$guard_tmp"' EXIT
printf '#!/usr/bin/env bash\nexit 0\n' > "$guard_tmp/claude"; chmod +x "$guard_tmp/claude"
guard_case(){ # role model effort registry-mutation -> rc
  python3 - "$root/templates/job-profiles.json" "$guard_tmp/p.json" "$4" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); r=x['modelRegistry']
if sys.argv[3]=='newmodel': r['x-new']={'provider':'haip','lifecycle':'active','roles':['worker'],'efforts':['max'],'routes':[]}
json.dump(x,open(sys.argv[2],'w'))
PY
  printf '{"modelId":"%s","effort":"%s","role":"%s"}' "$2" "$3" "$1" > "$guard_tmp/ctx.json"
  ( . "$root/lib/job-framework.sh"; job_profiles_file="$guard_tmp/p.json"; PATH="$guard_tmp:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake job_default_adapter "$guard_tmp/ctx.json" ) >/dev/null 2>&1
}
guard_case worker claude-sonnet-5-5 medium none && ok || bad guard-worker-ok
guard_case reviewer gpt-6.1-sol high none && ok || bad guard-reviewer-ok
guard_case worker x-new max newmodel && ok || bad guard-registry-model-ok
guard_case worker unknown-model medium none && bad guard-unknown-model || ok
guard_case worker gpt-6-luna low none && bad guard-wrong-role || ok
guard_case worker claude-sonnet-5-5 max none && bad guard-wrong-effort || ok

if [ "$fail" -ne 0 ]; then printf 'JOB_FRAMEWORK_FAIL failures=%s passes=%s\n' "$fail" "$pass"; exit 1; fi
printf 'JOB_FRAMEWORK_OK\n'
