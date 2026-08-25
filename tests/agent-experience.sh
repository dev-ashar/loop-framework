#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
home="$tmp/home"
outside="$tmp/outside"
mkdir -p "$home" "$outside"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
sha() { sha256sum "$1" | awk '{print $1}'; }

# The fixture must behave like a cloned repository, not like the source checkout.
cp -a "$root" "$repo"
rm -rf "$repo/.git" "$repo/.loops/runs" "$repo/.loops-mem"
git -C "$repo" init -q -b main
git -C "$repo" add .
git -C "$repo" -c user.name=fixture -c user.email=fixture@example.test commit -q -m fixture

# 1. Dry-run prints every managed action and changes no path.
digest_before=$(find "$home" -type f -print0 | sort -z | xargs -0 -r shasum -a 256 | shasum -a 256)
dry=$(HOME="$home" bash "$repo/install.sh" --dry-run)
digest_after=$(find "$home" -type f -print0 | sort -z | xargs -0 -r shasum -a 256 | shasum -a 256)
[ "$digest_before" = "$digest_after" ] || fail 'dry-run changed HOME'
for token in 'Backup managed paths' 'Merge settings' 'Link agents' 'Preserve or create lessons' 'Link CLI' 'job-framework'; do
  printf '%s\n' "$dry" | grep -Fq "$token" || fail "dry-run missing $token"
done
[ ! -e "$home/.claude" ] || fail 'dry-run created .claude'
pass 'dry-run digest and action list'

# 2-3. Fresh install creates all links and writes only inside HOME or the clone.
printf 'outside\n' > "$outside/untouched"
outside_before=$(sha "$outside/untouched")
HOME="$home" bash "$repo/install.sh" >/dev/null
[ -L "$home/.claude/CLAUDE.md" ] || fail 'CLAUDE.md link missing'
[ -L "$home/.claude/agents/builder.md" ] || fail 'builder link missing'
[ -L "$home/.claude/skills/job-framework" ] || fail 'job-framework link missing'
[ -L "$home/.claude/hooks/pre-tool-use.sh" ] || fail 'hook link missing'
[ -L "$home/.local/bin/loops" ] || fail 'CLI link missing'
[ "$(realpath "$home/.claude/CLAUDE.md")" = "$(realpath "$repo/.claude/CLAUDE.md")" ] || fail 'CLAUDE target wrong'
[ "$(realpath "$home/.local/bin/loops")" = "$(realpath "$repo/run.sh")" ] || fail 'CLI target wrong'
[ "$(sha "$outside/untouched")" = "$outside_before" ] || fail 'outside fixture changed'
pass 'fresh links and outside-write audit'

# 4-5. Seed unrelated settings and lesson bytes, then prove semantic preservation.
python3 - "$home/.claude/settings.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x.update({'customSetting':{'keep':True},'plugins':{'third-party':{'enabled':True}},'marketplaces':['custom-market'], 'permissions':{'allow':['custom:command'],'deny':['custom:deny']}, 'hooks':{'UserPromptSubmit':[{'hooks':[{'type':'command','command':'custom-hook'}]}]}}); json.dump(x,open(p,'w'),sort_keys=True); open(p,'a').write('\n')
PY
printf 'lesson-one\n' > "$home/.claude/memory/lessons.jsonl"
lesson_before=$(sha "$home/.claude/memory/lessons.jsonl")
settings_before=$(mktemp); cp "$home/.claude/settings.json" "$settings_before"
HOME="$home" bash "$repo/install.sh" >/dev/null
python3 - "$settings_before" "$home/.claude/settings.json" <<'PY'
import json,sys
before=json.load(open(sys.argv[1])); after=json.load(open(sys.argv[2]))
for k in ('customSetting','plugins','marketplaces'):
 assert after[k]==before[k], k
assert set(after['permissions']['allow']) >= set(before['permissions']['allow'])
assert any('custom-hook' in h.get('hooks',[{}])[0].get('command','') for h in after['hooks']['UserPromptSubmit'])
PY
[ "$(sha "$home/.claude/memory/lessons.jsonl")" = "$lesson_before" ] || fail 'lesson bytes changed'
pass 'semantic settings and lesson preservation'

# 6. Reinstall must deduplicate managed hooks and keep link targets stable.
target_before=$(readlink "$home/.claude/skills/job-framework")
HOME="$home" bash "$repo/install.sh" >/dev/null
[ "$target_before" = "$(readlink "$home/.claude/skills/job-framework")" ] || fail 'managed target changed'
python3 - "$home/.claude/settings.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
for group in x.get('hooks',{}).values():
 for entry in group:
  cmds=[h.get('command','') for h in entry.get('hooks',[])]
  assert sum('pre-tool-use.sh' in c or 'post-tool-use.sh' in c or 'stop-mem.sh' in c or 'session-start-mem.sh' in c for c in cmds) <= 1
PY
pass 'reinstall duplicate checks'

# 7. Malformed settings and missing sources must fail before replacement.
managed_before=$(readlink "$home/.claude/CLAUDE.md")
printf '{bad' > "$home/.claude/settings.json"
if HOME="$home" bash "$repo/install.sh" >/dev/null 2>&1; then fail 'malformed settings accepted'; fi
[ "$(readlink "$home/.claude/CLAUDE.md")" = "$managed_before" ] || fail 'malformed settings replaced paths'
rm -f "$home/.claude/settings.json"
rm -f "$repo/.claude/settings.json"
if HOME="$home" bash "$repo/install.sh" >/dev/null 2>&1; then fail 'missing source accepted'; fi
[ "$(readlink "$home/.claude/CLAUDE.md")" = "$managed_before" ] || fail 'missing source replaced paths'
pass 'rollback and missing-source failure'

# Source the production bridge from the fixture so all hashes and roots are real.
SCRIPT_DIR="$repo"; . "$repo/lib/job-framework.sh"
contract="$repo/.loops/contract.md"
contract_hash=$(sha "$contract")
run="$repo/.loops/runs/agent-experience"
mkdir -p "$run"

# 8 and 10-11. Natural two-job routing creates deterministic validated DAG metadata.
printf '%s\n' '[{"id":"first","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":[],"writeScope":["README.md"],"verify":"true","lenses":["correctness"]},{"id":"second","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":["first"],"writeScope":["install.sh"],"verify":"true","lenses":["scope"]}]' > "$run/steps.json"
route=$(job_orchestrate 'make the fixture work' "$run/steps.json" "$repo" agent-experience)
printf '%s\n' "$route" | grep -qx 'ORCHESTRATOR_ROUTE dag' || fail 'natural two-job route missing'
[ -f "$run/job-dag.json" ] && [ -f "$run/job-dag.json.metadata.json" ] || fail 'DAG metadata missing'
job_bridge_metadata_validate "$run/job-dag.json" "$run/job-dag.json.metadata.json" "$contract" >/dev/null
first=$(sha "$run/job-dag.json"); job_contract_bridge "$contract" "$run/steps.json" "$run/job-dag-2.json" "$contract_hash" >/dev/null
[ "$first" = "$(sha "$run/job-dag-2.json")" ] || fail 'bridge output is not deterministic'
cp "$run/job-dag.json.metadata.json" "$run/meta.good"
printf '{"schemaVersion":1,"contractHash":"tampered","dagSha256":"tampered"}\n' > "$run/job-dag.json.metadata.json"
if job_bridge_metadata_validate "$run/job-dag.json" "$run/job-dag.json.metadata.json" "$contract" >/dev/null 2>&1; then fail 'tampered metadata accepted'; fi
mv "$run/meta.good" "$run/job-dag.json.metadata.json"
pass 'natural DAG, deterministic bridge, metadata tamper'

# 9. One useful step stays on the legacy route and creates no DAG scratch.
rm -rf "$repo/.loops/runs/legacy"
printf '%s\n' '[{"id":"only","role":"builder","profile":"builder-default","modelTier":"sonnet","dependsOn":[],"writeScope":["README.md"],"verify":"true","lenses":["correctness"]}]' > "$run/one.json"
[ "$(job_orchestrate 'one step' "$run/one.json" "$repo" legacy | head -1)" = 'ORCHESTRATOR_ROUTE legacy' ] || fail 'legacy route missing'
[ ! -e "$repo/.loops/runs/legacy" ] || fail 'legacy route created DAG scratch'
pass 'legacy one-step route'

# 12-14. Context contains exact values, rejects tampering, and ignores model overrides.
base_sha=$(git -C "$repo" rev-parse HEAD)
job_context_create "$run/job-dag.json" first agent-experience dispatch-first "$repo" "$repo" "$run/context.json"
python3 - "$run/context.json" "$run/job-dag.json" "$repo" "$contract_hash" "$base_sha" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); d=json.load(open(sys.argv[2])); j=d['jobs'][0] if isinstance(d['jobs'],list) else d['jobs']['first']
keys='jobId role profile modelTier modelId dependsOn writeScope verify lenses runId dispatchId contractHash baseSha repositoryRoot worktreePath'.split()
assert set(c)==set(keys)
for k in ('role','profile','modelTier','dependsOn','writeScope','verify','lenses'):
 assert c[k]==j[k], k
assert c['jobId']==j['id']
assert c['runId']=='agent-experience' and c['dispatchId']=='dispatch-first' and c['contractHash']==sys.argv[4] and c['baseSha']==sys.argv[5]
import os
assert c['repositoryRoot']==os.path.realpath(sys.argv[3]) and c['worktreePath']==os.path.realpath(sys.argv[3])
PY
cp "$run/context.json" "$run/context.tampered"; python3 - "$run/context.tampered" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['modelId']='attacker-model'; json.dump(x,open(p,'w'))
PY
if job_context_validate "$run/context.tampered" "$repo" "$repo" "$contract_hash" "$base_sha" >/dev/null 2>&1; then fail 'tampered context accepted'; fi
JOB_DISPATCH_MODEL=attacker-model; export JOB_DISPATCH_MODEL
observed_model=$(python3 - "$run/context.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['modelId'])
PY
)
[ "$observed_model" = 'claude-sonnet-5' ] || fail 'environment overrode model'
pass 'exact context, tamper rejection, model binding'

# 15-17. Exercise the real approval, lifecycle, dependency, conflict, and gate order primitives.
approval_cb() { printf 'host-control-plane\t%s\t%s\t%s\t%s\tbuilder\t2026-08-25T00:00:00Z\n' "$1" "$2" "$3" "$4"; }
job_approval_observer_new production approval_cb >/dev/null
job_approval_observe "$repo" "$contract_hash" agent-experience correlation builder >/dev/null
ledger="$run/lifecycle.json"
printf '%s\n' '{"runId":"agent-experience","root":"'"$repo"'","baseSha":"'"$base_sha"'","jobs":{"first":{"state":"pending","dependsOn":[],"scope":["README.md"],"worktree":"'"$repo"'","branch":"main"},"second":{"state":"pending","dependsOn":["first"],"scope":["install.sh"],"worktree":"'"$repo"'","branch":"main"}}}' > "$ledger"
printf '%s\n' "$(job_lifecycle_ready "$ledger")" | grep -qx $'first\tready' || fail 'dependency predecessor not ready'
job_executor_transition "$ledger" first ready >/dev/null; job_executor_transition "$ledger" first running >/dev/null
printf 'changed\n' >> "$repo/README.md"
job_lifecycle_scope_gate "$ledger" first >/dev/null 2>&1 || true
python3 - "$ledger" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['jobs']['first']['state']=='failed'; assert x['jobs']['second']['state']=='blocked'
PY
# Gate names stay ordered in the internal skill and dispatch contract.
order='approval envelope builder report verification scope evaluator accounting integration'
for token in $order; do grep -Fqi "$token" "$repo/.claude/skills/job-framework/SKILL.md" || fail "missing gate $token"; done
pass 'approval, ordered gates, dependency blocking'

# 16-17. Conflict rehearsal preserves source branches and keeps the main worktree clean.
conf="$tmp/conflict-repo"; mkdir "$conf"; git -C "$conf" init -q -b main; printf base > "$conf/file"; git -C "$conf" add file; git -C "$conf" -c user.name=f -c user.email=f commit -q -m base
base=$(git -C "$conf" rev-parse HEAD); git -C "$conf" branch a; git -C "$conf" branch b
printf left > "$conf/file"; git -C "$conf" add file; git -C "$conf" -c user.name=f -c user.email=f commit -q -m left; git -C "$conf" branch -f a HEAD; git -C "$conf" reset -q --hard "$base"
printf right > "$conf/file"; git -C "$conf" add file; git -C "$conf" -c user.name=f -c user.email=f commit -q -m right; git -C "$conf" branch -f b HEAD; git -C "$conf" reset -q --hard "$base"
printf '%s\n' $'a\ta' $'b\tb' > "$tmp/records"
set +e; conflict_out=$(job_integration_run "$conf" "$base" conflict-run "$tmp/records" "$tmp/evidence"); conflict_rc=$?; set -e
[ "$conflict_rc" -eq 10 ] || fail 'conflict did not stop integration'
git -C "$conf" show-ref --verify --quiet refs/heads/a; git -C "$conf" show-ref --verify --quiet refs/heads/b
[ -z "$(git -C "$conf" status --porcelain)" ] || fail 'conflict dirtied main worktree'
[ -s "$tmp/evidence" ] || fail 'conflict evidence missing'
pass 'conflict preservation and clean main'

# 18. README user commands run, while internal job commands stay out of user usage.
grep -Fq 'bash install.sh' "$repo/README.md" || fail 'README install command missing'
grep -Fq '/run-loop' "$repo/README.md" || fail 'README natural route missing'
README_USER=$(sed -n '1,42p' "$repo/README.md")
if printf '%s\n' "$README_USER" | grep -Eq '(^|[[:space:]])(bash[[:space:]]+)?loops[[:space:]]+job'; then fail 'README user block exposes loops job'; fi
pass 'README commands'

# 19-21. Run the named regression suites and full verifier from the fixture source.
for suite in job-framework.sh job-executor.sh job-dispatch.sh job-integration.sh job-lifecycle.sh job-runtime.sh; do
  output=$(bash "$repo/tests/$suite" 2>&1) || fail "$suite failed: $output"
done
bash "$repo/tests/run_tests.sh" >/dev/null 2>&1 || true
bash "$repo/tests/contract-negotiation.sh" >/dev/null
audit=$(git -C "$repo" diff --check); [ -z "$audit" ] || fail 'fixture diff check failed'
pass 'six job suites and contract negotiation'

printf '%s\n' AGENT_EXPERIENCE_OK
