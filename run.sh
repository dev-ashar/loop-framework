#!/usr/bin/env bash
# LOOPS runner — bootstrap a loop's state dir in the current project, then hand
# off to a native primitive. Keeps state on disk so a crashed run is recoverable.
#
#   ./run.sh init                 # create .loops/ from templates
#   ./run.sh init "<goal>"        # init and seed the contract goal
#   ./run.sh status               # show contract + progress + tail of log
#
# After `init`, drive the loop with the native primitives:
#   /contract   negotiate acceptance criteria into .loops/contract.md
#   /goal ...   run a measurable loop with a stop condition
#   /loop 5m .. run on an interval

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
LOOPDIR=".loops"

cmd="${1:-status}"

case "$cmd" in
  init)
    mkdir -p "$LOOPDIR"
    for f in contract.md progress.md log.md feature_list.json; do
      if [ ! -f "$LOOPDIR/$f" ]; then
        cp "$TEMPLATES/$f" "$LOOPDIR/$f"
        echo "created $LOOPDIR/$f"
      else
        echo "kept $LOOPDIR/$f (already exists)"
      fi
    done
    if [ -n "${2:-}" ]; then
      # Seed the goal line in the fresh contract.
      tmp="$(mktemp)"
      awk -v g="$2" 'BEGIN{done=0} /^<one sentence/ && !done {print g; done=1; next} {print}' \
        "$LOOPDIR/contract.md" > "$tmp" && mv "$tmp" "$LOOPDIR/contract.md"
      echo "seeded goal: $2"
    fi
    echo "Next: run /contract to negotiate acceptance criteria."
    ;;
  status)
    [ -d "$LOOPDIR" ] || { echo "No .loops/ here. Run: $0 init"; exit 0; }
    echo "=== contract.md ==="; sed -n '1,20p' "$LOOPDIR/contract.md" 2>/dev/null || true
    echo; echo "=== progress.md ==="; sed -n '1,20p' "$LOOPDIR/progress.md" 2>/dev/null || true
    echo; echo "=== log.md (tail) ==="; tail -n 10 "$LOOPDIR/log.md" 2>/dev/null || true
    ;;
  *)
    echo "usage: $0 {init [\"goal\"] | status}"; exit 1
    ;;
esac
