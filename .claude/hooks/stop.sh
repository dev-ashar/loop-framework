#!/usr/bin/env bash
# LOOPS reflex: clean exit. Contract: Stop hook, fires when the agent finishes a
# turn. Clears a stale run marker so a crashed loop doesn't look active. Always
# exits 0 — a clean-up step must never block the stop.

set -uo pipefail

# Remove the "loop in progress" marker if present. Harmless if absent.
[ -f ".loops/.running" ] && rm -f ".loops/.running" 2>/dev/null || true

exit 0
