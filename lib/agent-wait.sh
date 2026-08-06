#!/usr/bin/env bash
# Poll a background subagent's transcript until it is genuinely finished.
#
# Completion notifications are not reliable — an agent can end its turn without
# the harness emitting a result record, which looks identical to "still running"
# and cost us several minutes of watching a finished agent. This polls the
# transcript instead, which is written by the agent itself.
#
#   agent-wait <task-id> [timeout-seconds]
#
# Done means: the last record's stop_reason is end_turn AND the file has been
# quiet for QUIET seconds. The quiet window matters because an agent that is
# mid-tool-loop also passes through end_turn-shaped records.
#
# Prints DONE / TIMEOUT and, on DONE, the agent's final text.

set -euo pipefail

task_id="${1:-}"
timeout="${2:-900}"
[ -n "$task_id" ] || { echo "usage: agent-wait <task-id> [timeout-seconds]" >&2; exit 2; }

QUIET=15
POLL=5

tasks_dir="$(dirname "$(ls -t /tmp/claude-501/*/*/tasks/"$task_id".output 2>/dev/null | head -1)")"
out="$tasks_dir/$task_id.output"
[ -f "$out" ] || { echo "no transcript for $task_id" >&2; exit 1; }

waited=0
while [ "$waited" -lt "$timeout" ]; do
  mtime=$(stat -f %m "$out")
  now=$(date +%s)
  idle=$(( now - mtime ))

  if [ "$idle" -ge "$QUIET" ] && python3 - "$out" <<'PY'
import json,sys
recs=[l for l in open(sys.argv[1]) if l.strip()]
if not recs: sys.exit(1)
try: m=json.loads(recs[-1]).get("message") or {}
except Exception: sys.exit(1)
sys.exit(0 if m.get("stop_reason")=="end_turn" else 1)
PY
  then
    echo "DONE after ${waited}s (idle ${idle}s)"
    python3 - "$out" <<'PY'
import json,sys
recs=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
m=recs[-1].get("message") or {}
for c in (m.get("content") or []):
    if isinstance(c,dict) and c.get("type")=="text": print(c["text"])
PY
    exit 0
  fi

  sleep "$POLL"
  waited=$(( waited + POLL ))
done

echo "TIMEOUT after ${timeout}s (last write $(date -r "$out" '+%H:%M:%S'))"
exit 1
