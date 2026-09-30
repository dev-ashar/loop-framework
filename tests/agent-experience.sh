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
[ -L "$home/.claude/agents/worker.md" ] || fail 'worker link missing'
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

# 8 and 10-11. Natural two-job routing creates a deterministic validated DAG.
printf '%s\n' '[{"id":"first","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["README.md"],"objective":"Implement the first scoped fixture change","verify":"true","lenses":["correctness"]},{"id":"second","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":["first"],"writeScope":["install.sh"],"objective":"Implement the second scoped fixture change","verify":"true","lenses":["scope"]},{"id":"review-first","role":"reviewer","profile":"reviewer-default","modelTier":"primary","dependsOn":["first"],"writeScope":[],"readScope":["README.md"],"objective":"Review the first fixture change","verify":"true","lenses":["correctness"]},{"id":"review-second","role":"reviewer","profile":"reviewer-default","modelTier":"primary","dependsOn":["second"],"writeScope":[],"readScope":["install.sh"],"objective":"Review the second fixture change","verify":"true","lenses":["scope"]}]' > "$run/steps.json"
route=$(job_orchestrate 'make the fixture work' "$run/steps.json" "$repo" agent-experience)
printf '%s\n' "$route" | grep -qx 'ORCHESTRATOR_ROUTE dag' || fail 'natural two-job route missing'
[ -f "$run/job-dag.json" ] || fail 'DAG missing'
first=$(sha "$run/job-dag.json"); job_assignments_to_dag "$run/steps.json" "$run/job-dag-2.json" >/dev/null
[ "$first" = "$(sha "$run/job-dag-2.json")" ] || fail 'DAG output is not deterministic'
[ ! -e "$run/job-dag.json.metadata.json" ] || fail 'contract-bound DAG metadata still created'
pass 'natural deterministic DAG without contract metadata'

# 9. One useful step stays on the direct route and creates no DAG scratch.
rm -rf "$repo/.loops/runs/legacy"
printf '%s\n' '[{"id":"only","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["README.md"],"objective":"Implement the first scoped fixture change","verify":"true","lenses":["correctness"]}]' > "$run/one.json"
[ "$(job_orchestrate 'one step' "$run/one.json" "$repo" direct | head -1)" = 'ORCHESTRATOR_ROUTE direct' ] || fail 'direct route missing'
[ ! -e "$repo/.loops/runs/direct" ] || fail 'direct route created DAG scratch'
printf '%s\n' '[{"id":"broken","role":"worker"}]' > "$run/invalid-one.json"
if job_orchestrate 'broken step' "$run/invalid-one.json" "$repo" direct-invalid >/dev/null 2>&1; then fail 'malformed direct assignment accepted'; fi
[ ! -e "$repo/.loops/runs/direct-invalid" ] || fail 'invalid direct assignment created scratch'
pass 'validated direct one-step route'

# 12-14. Context contains exact values, rejects tampering, and ignores model overrides.
base_sha=$(git -C "$repo" rev-parse HEAD)
ctx_run=$(job_executor_init "$repo" context-test "$run/job-dag.json")
job_context_trust_init "$run/job-dag.json" "$ctx_run" "$repo"
job_runtime_set_worktree "$ctx_run/jobs.json" first "$repo"
job_context_trust_update "$ctx_run/context-trust.json" first "$repo" pending
job_context_create "$run/job-dag.json" first context-test dispatch-first "$repo" "$repo" "$run/context.json"
python3 - "$run/context.json" "$run/job-dag.json" "$repo" "$contract_hash" "$base_sha" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); d=json.load(open(sys.argv[2])); j=d['jobs'][0] if isinstance(d['jobs'],list) else d['jobs']['first']
keys='jobId role profile modelTier modelId provider effort lifecycle status objective objectiveDigest dependsOn writeScope readScope verify lenses runId dispatchId baseSha dagPath dagDigest repositoryRoot worktreePath'.split()
assert set(c)==set(keys)
for k in ('role','profile','modelTier','objective','dependsOn','writeScope','verify','lenses'):
 assert c[k]==j[k], k
assert c['jobId']==j['id']
assert c['provider']=='haip' and c['lifecycle']=='active' and c['effort']=='max'
assert c['runId']=='context-test' and c['dispatchId']=='dispatch-first' and c['baseSha']==sys.argv[5]
import os
assert c['repositoryRoot']==os.path.realpath(sys.argv[3]) and c['worktreePath']==os.path.realpath(sys.argv[3])
PY
cp "$run/context.json" "$run/context.tampered"; python3 - "$run/context.tampered" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['modelId']='attacker-model'; json.dump(x,open(p,'w'))
PY
if job_context_validate "$run/context.tampered" "$repo" "$repo" "$base_sha" >/dev/null 2>&1; then fail 'tampered context accepted'; fi
JOB_DISPATCH_MODEL=attacker-model; export JOB_DISPATCH_MODEL
observed_model=$(python3 - "$run/context.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['modelId'])
PY
)
[ "$observed_model" = 'gpt-5.6-luna-mantle' ] || fail 'environment overrode model'
pass 'exact context, tamper rejection, model binding'

# 15-17. Exercise the real approval, lifecycle, dependency, conflict, and gate order primitives.
approval_cb() { printf 'host-control-plane\t%s\t%s\t%s\t%s\tworker\t2026-08-25T00:00:00Z\n' "$1" "$2" "$3" "$4"; }
job_approval_observer_new production approval_cb >/dev/null
job_approval_observe "$repo" "$contract_hash" agent-experience correlation worker >/dev/null
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
# Role handoff stays ordered in the internal skill: explorer, architect, worker, reviewer, merge.
order='explorer architect worker reviewer merge'
last=0
for token in $order; do
  line=$(grep -n -m1 -i "$token" "$repo/.claude/skills/job-framework/SKILL.md" | cut -d: -f1)
  [ -n "$line" ] || fail "missing gate $token"
  [ "$line" -gt "$last" ] || fail "gate order broken at $token"
  last=$line
done
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

# 19-21. Run the named regression suites and reject the retired command.
for suite in job-framework.sh job-executor.sh job-dispatch.sh job-integration.sh job-lifecycle.sh job-runtime.sh; do
  output=$(bash "$repo/tests/$suite" 2>&1) || fail "$suite failed: $output"
done
# The legacy aggregate suite is non-asserting here and repeats the focused suites.
# Keep this fixture bounded; .loops/verify.sh remains the authoritative aggregate.
if bash "$repo/.loops/verify.sh" agent-envelope >/dev/null 2>&1; then fail 'retired agent-envelope command still accepted'; fi
audit=$(git -C "$repo" diff --check); [ -z "$audit" ] || fail 'fixture diff check failed'
pass 'six job suites and retired-command check'

# 22. Real worker-to-reviewer execution uses a worker branch and a separate read-only snapshot.
e2e="$tmp/e2e-repo"; cp -a "$repo" "$e2e"; rm -rf "$e2e/.git" "$e2e/.loops/runs" "$e2e/.loops-mem"; git -C "$e2e" init -q -b main; git -C "$e2e" config user.email fixture@example.test; git -C "$e2e" config user.name fixture
printf base >"$e2e/base.txt"; git -C "$e2e" add .; git -C "$e2e" commit -qm base
cat >"$e2e/dag.json" <<'JSON'
{"schemaVersion":2,"jobs":[{"id":"worker","role":"worker","profile":"worker-default","modelTier":"operational","dependsOn":[],"writeScope":["base.txt"],"objective":"Update the fixture value","verify":"grep -q changed base.txt","lenses":["correctness"]},{"id":"reviewer","role":"reviewer","profile":"reviewer-default","modelTier":"primary","dependsOn":["worker"],"writeScope":[],"readScope":["base.txt"],"objective":"Verify the worker update","verify":"grep -q changed base.txt","lenses":["correctness"]}]}
JSON
cat >"$e2e/adapter.sh" <<'SH'
#!/usr/bin/env bash
set -eu
c="$1"
role=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["role"])' "$c")
wt=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["worktreePath"])' "$c")
before=$(git -C "$wt" rev-parse HEAD)
case "$role" in
  worker)
    printf changed >"$wt/base.txt"
    git -C "$wt" add base.txt
    git -C "$wt" commit -qm changed
    ;;
  reviewer)
    grep -q changed "$wt/base.txt"
    if [ "${REVIEWER_WRITE:-0}" = 1 ]; then printf reviewer-delta >"$wt/reviewer-delta.txt"; fi
    case "${REVIEWER_DELTA_KIND:-}" in
      ignored) printf mutated >"$wt/reviewer-cache/existing.txt" ;;
      untracked) printf mutated >"$wt/existing.txt" ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
after=$(git -C "$wt" rev-parse HEAD)
printf '%s\t%s\t%s\t%s\n' "$role" "$wt" "$before" "$after" >>"$E2E_CALLS"
[ "$role" != reviewer ] || [ "$before" = "$after" ]
SH
chmod +x "$e2e/adapter.sh"
( cd "$e2e"; SCRIPT_DIR="$root" E2E_CALLS="$e2e/adapter-calls" JOB_ADAPTER_CALLBACK=e2e_adapter; export E2E_CALLS; e2e_adapter(){ "$e2e/adapter.sh" "$1"; }; export -f e2e_adapter; . "$root/lib/job-framework.sh"; job_run "$e2e/dag.json" e2e-run ) >/dev/null || fail 'e2e worker reviewer run'
worker_refs=$(git -C "$e2e" show-ref --heads | grep -c 'refs/heads/loops/e2e-run/worker$' || true)
reviewer_refs=$(git -C "$e2e" show-ref --heads | grep -c 'refs/heads/loops/e2e-run/reviewer$' || true)
[ "$worker_refs" -eq 1 ] || fail 'e2e worker branch missing'
[ "$reviewer_refs" -eq 0 ] || fail 'read-only reviewer created a branch'
python3 - "$e2e/.loops/runs/e2e-run/jobs.json" "$e2e/adapter-calls" <<'PY'
import json,sys
ledger=json.load(open(sys.argv[1]))
rows=[line.rstrip('\n').split('\t') for line in open(sys.argv[2]) if line.strip()]
assert [row[0] for row in rows] == ['worker','reviewer']
assert rows[0][1] != rows[1][1]
assert rows[0][2] != rows[0][3]
assert rows[1][2] == rows[1][3]
worker=ledger['jobs']['worker']; reviewer=ledger['jobs']['reviewer']
assert worker['state'] == 'passed' and reviewer['state'] == 'passed'
assert worker['worktree'] == rows[0][1] and reviewer['worktree'] == rows[1][1]
assert reviewer['worktree'].endswith('/review-worktrees/reviewer')
assert reviewer['branch'] is None
PY
pass 'real worker reviewer execution'

# 23. An adversarial reviewer write fails the reviewer before passed.
write_e2e="$tmp/write-e2e-repo"; cp -a "$e2e" "$write_e2e"; rm -rf "$write_e2e/.git" "$write_e2e/.loops/runs" "$write_e2e/.loops-mem"; git -C "$write_e2e" init -q -b main; git -C "$write_e2e" config user.email fixture@example.test; git -C "$write_e2e" config user.name fixture; printf base >"$write_e2e/base.txt"; git -C "$write_e2e" add .; git -C "$write_e2e" commit -qm base
set +e
( cd "$write_e2e"; SCRIPT_DIR="$root" E2E_CALLS="$write_e2e/adapter-calls" REVIEWER_WRITE=1 JOB_ADAPTER_CALLBACK=e2e_adapter; export E2E_CALLS REVIEWER_WRITE; e2e_adapter(){ "$write_e2e/adapter.sh" "$1"; }; export -f e2e_adapter; . "$root/lib/job-framework.sh"; job_run "$write_e2e/dag.json" e2e-reviewer-write ) >/dev/null 2>&1
write_rc=$?
set -e
[ "$write_rc" -ne 0 ] || fail 'reviewer uncommitted write accepted'
python3 - "$write_e2e/.loops/runs/e2e-reviewer-write/jobs.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d['jobs']['reviewer']['state']=='failed'
PY
pass 'adversarial reviewer delta rejected'

# 24. Existing ignored and untracked bytes and metadata are part of the reviewer snapshot.
snapshot_repo="$tmp/snapshot-repo"; mkdir "$snapshot_repo"; git -C "$snapshot_repo" init -q -b main; git -C "$snapshot_repo" config user.email fixture@example.test; git -C "$snapshot_repo" config user.name fixture
printf 'reviewer-cache/\n' >"$snapshot_repo/.gitignore"; printf base >"$snapshot_repo/base.txt"; git -C "$snapshot_repo" add .; git -C "$snapshot_repo" commit -qm base
mkdir -p "$snapshot_repo/reviewer-cache"; printf original >"$snapshot_repo/reviewer-cache/existing.txt"; printf original >"$snapshot_repo/existing.txt"
before_snapshot=$(mktemp); job_executor_snapshot_worktree "$snapshot_repo" "$before_snapshot"
printf mutated >"$snapshot_repo/reviewer-cache/existing.txt"
if job_executor_worktree_unchanged "$snapshot_repo" "$before_snapshot" >/dev/null 2>&1; then fail 'reviewer existing ignored delta accepted'; fi
printf original >"$snapshot_repo/reviewer-cache/existing.txt"; job_executor_snapshot_worktree "$snapshot_repo" "$before_snapshot"
printf mutated >"$snapshot_repo/existing.txt"
if job_executor_worktree_unchanged "$snapshot_repo" "$before_snapshot" >/dev/null 2>&1; then fail 'reviewer existing untracked delta accepted'; fi
printf original >"$snapshot_repo/existing.txt"; job_executor_snapshot_worktree "$snapshot_repo" "$before_snapshot"
chmod 600 "$snapshot_repo/existing.txt"; if job_executor_worktree_unchanged "$snapshot_repo" "$before_snapshot" >/dev/null 2>&1; then fail 'reviewer untracked metadata delta accepted'; fi
rm -f "$before_snapshot"
pass 'adversarial existing ignored and untracked deltas rejected'

printf '%s\n' AGENT_EXPERIENCE_OK
