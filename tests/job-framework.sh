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
{"schemaVersion":1,"jobs":[{"id":"build-a","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":[],"writeScope":["lib/a.sh"],"verify":"true","lenses":["correctness"]},{"id":"build-b","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":["build-a"],"writeScope":["lib/b.sh"],"verify":"true","lenses":["scope"]}]}
JSON
expect_ok valid-dag bash run.sh job validate "$t/valid.json"
[ "$(bash run.sh job schedule "$t/valid.json" 2>/dev/null)" = $'build-a\nbuild-b' ] && ok || bad schedule
[ "$(bash run.sh job route builder-default sonnet 2>/dev/null)" = claude-sonnet-5 ] && ok || bad route
expect_fail unknown-tier bash run.sh job route builder-default unknown

cat > "$t/nonbuilder.json" <<'JSON'
{"schemaVersion":1,"jobs":[{"id":"plan","role":"planner","profile":"builder-default","modelTier":"sonnet","dependsOn":[],"writeScope":["x"],"verify":"true","lenses":["correctness"]}]}
JSON
expect_token nonbuilder DAG_JOB_INVALID bash run.sh job validate "$t/nonbuilder.json"
cat > "$t/unknown.json" <<'JSON'
{"schemaVersion":1,"jobs":[],"extra":1}
JSON
expect_token unknown-property DAG_SCHEMA_INVALID bash run.sh job validate "$t/unknown.json"
printf '%s\n' '{"schemaVersion":1,"schemaVersion":1,"jobs":[]}' > "$t/duplicate.json"
expect_token duplicate-key DAG_DUPLICATE_KEY bash run.sh job validate "$t/duplicate.json"
for version in 0 2; do jq --argjson v "$version" '.schemaVersion=$v' "$t/valid.json" > "$t/v.json"; expect_token "version-$version" DAG_SCHEMA_INVALID bash run.sh job validate "$t/v.json"; done

cat > "$t/self.json" <<'JSON'
{"schemaVersion":1,"jobs":[{"id":"a","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":["a"],"writeScope":["x"],"verify":"true","lenses":["correctness"]}]}
JSON
expect_token self-dependency DAG_SELF_DEPENDENCY bash run.sh job validate "$t/self.json"
cat > "$t/cycle.json" <<'JSON'
{"schemaVersion":1,"jobs":[{"id":"a","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":["b"],"writeScope":["x"] ,"verify":"true","lenses":["correctness"]},{"id":"b","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":["a"],"writeScope":["y"],"verify":"true","lenses":["correctness"]}]}
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

if [ "$fail" -ne 0 ]; then printf 'JOB_FRAMEWORK_FAIL failures=%s passes=%s\n' "$fail" "$pass"; exit 1; fi
printf 'JOB_FRAMEWORK_OK\n'
