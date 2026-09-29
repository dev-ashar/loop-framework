#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$root/tests/bench/fixtures.json" "$root/templates/job-profiles.json" <<'PY'
import json,sys
fixtures=json.load(open(sys.argv[1])); profiles=json.load(open(sys.argv[2]))
if fixtures.get('offline') is not True or fixtures.get('schemaVersion') != 1: raise SystemExit('BENCH_FIXTURE_INVALID')
if not fixtures.get('lanes') or not fixtures.get('tasks'): raise SystemExit('BENCH_FIXTURE_INVALID')
if any(x.get('provider') != 'haip' for x in profiles['modelRegistry'].values()): raise SystemExit('BENCH_NON_HAIP_ROUTE')
print('BENCH_OFFLINE_OK')
PY
