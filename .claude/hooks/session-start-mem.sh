#!/usr/bin/env bash
# SessionStart: put this repo's durable memory in front of the agent before it is
# asked anything.
#
# Recall has to be automatic or the store rots. The global lessons.jsonl proved
# that: 13 entries accumulated and nothing ever read them, because recall depended
# on a skill remembering to call `lesson check`. A hook does not forget.
#
# Never fail a session over memory: every path exits 0.

set -uo pipefail

loops=$(command -v loops 2>/dev/null) || exit 0

out=$("$loops" mem show 20 2>/dev/null) || exit 0
[ -n "$out" ] || exit 0

printf 'Durable memory for this repo and branch. Facts already established — do not\n'
printf 're-derive them. Add to it with `loops mem fact "<repo truth>"` and\n'
printf '`loops mem note "<what you did or ruled out>"`.\n\n'
printf '%s\n' "$out"
exit 0
