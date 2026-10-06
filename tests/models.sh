#!/usr/bin/env bash
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root"
fail=0; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
bad(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
# Stub curl serves a mocked live model list.
cat > "$tmp/curl" <<'SH'
#!/usr/bin/env bash
printf '{"data":[{"id":"claude-sonnet-5-5"},{"id":"gpt-6-luna"},{"id":"gpt-6.1-sol"},{"id":"new-model-x"}]}\n'
SH
chmod +x "$tmp/curl"
mkdir -p "$tmp/agents"; cp .claude/agents/*.md "$tmp/agents/"
cp templates/job-profiles.json "$tmp/p.json"
run(){ PATH="$tmp:$PATH" ANTHROPIC_BASE_URL=https://haip.test ANTHROPIC_AUTH_TOKEN=fake LOOPS_AGENTS_DIR="$tmp/agents" LOOPS_PROFILES_FILE="$tmp/p.json" bash run.sh models "$@"; }
fm(){ grep -m1 "^$2:" "$tmp/agents/$1.md" | sed 's/^[a-z]*: *//'; }

# unknown id rejected, nothing changes
if run set explorer nope-model >/dev/null 2>&1; then bad unknown-accepted; fi
[ "$(fm explorer model)" = gpt-6-luna ] || bad unknown-mutated

# interactive menu: ids sort -> claude-sonnet-5-5(1) gpt-6-luna(2) gpt-6.1-sol(3) new-model-x(4)
out=$(printf '4\n' | run set explorer) || bad menu-failed
printf '%s\n' "$out" | grep -q '\*  *2) gpt-6-luna' || bad menu-current-mark
[ "$(fm explorer model)" = new-model-x ] || bad menu-frontmatter
[ "$(fm explorer effort)" = low ] || bad menu-effort-kept
python3 - "$tmp/p.json" <<'PY' || bad menu-registry
import json,sys
p=json.load(open(sys.argv[1])); r=p['modelRegistry']
assert p['profiles']['explorer-default']['models']['primary']=='new-model-x'
assert r['new-model-x']['provider']=='haip' and r['new-model-x']['lifecycle']=='active'
assert 'gpt-6-luna' not in r, 'last role moved away: pruned'
assert 'claude-sonnet-5-5' in r
PY
bash run.sh job profiles >/dev/null 2>&1 || true
LOOPS_AGENTS_DIR="$tmp/agents" bash -c '. lib/job-framework.sh; job_profiles_file="$1"; job_validate_profiles "$1"' _ "$tmp/p.json" | grep -q PROFILE_OK || bad profiles-after-menu

# invalid menu choice rejected
if printf '9\n' | run set explorer >/dev/null 2>&1; then bad menu-range-accepted; fi
if printf 'x\n' | run set explorer >/dev/null 2>&1; then bad menu-nonnumeric-accepted; fi

# explicit id with --effort; shared model keeps registry entry while another role uses it
run set reviewer claude-sonnet-5-5 --effort medium >/dev/null || bad explicit-failed
[ "$(fm reviewer model)" = claude-sonnet-5-5 ] || bad explicit-model
[ "$(fm reviewer effort)" = medium ] || bad explicit-effort
python3 - "$tmp/p.json" <<'PY' || bad explicit-registry
import json,sys
r=json.load(open(sys.argv[1]))['modelRegistry']
assert 'reviewer' in r['claude-sonnet-5-5']['roles'] and 'medium' in r['claude-sonnet-5-5']['efforts']
assert 'reviewer' not in r['gpt-6.1-sol']['roles'] and 'merge' in r['gpt-6.1-sol']['roles']
PY

# --force skips the live check when HAIP is unreachable
printf '#!/usr/bin/env bash\nexit 22\n' > "$tmp/curl"
if run set worker offline-model >/dev/null 2>&1; then bad offline-without-force; fi
run set worker offline-model --force >/dev/null || bad force-failed
[ "$(fm worker model)" = offline-model ] || bad force-frontmatter

if [ "$fail" -ne 0 ]; then printf 'MODELS_FAIL failures=%s\n' "$fail"; exit 1; fi
printf 'MODELS_OK\n'
