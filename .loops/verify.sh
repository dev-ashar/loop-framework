set -euo pipefail
cd /Users/devashar/Documents/DS/workspace/loops

# D1
test ! -e "$HOME/.claude/.i-have-adhd-always"
for h in "$HOME/.claude/plugins/cache/i-have-adhd/i-have-adhd/0.1.0/hooks/always-on.sh" \
         "$HOME/.claude/plugins/marketplaces/i-have-adhd/hooks/always-on.sh"; do
  [ -f "$h" ] || continue
  out=$(sh "$h"); [ -z "$out" ]
done
jq -e '.enabledPlugins["i-have-adhd@i-have-adhd"] == true' "$HOME/.claude/settings.json" >/dev/null

# D2
test -s .loops/haip-config.md
for tok in gpt-5.6-terra-mantle gpt-5.6-luna-mantle gpt-5.6-sol \
           '## Tier mapping' '## Context window'; do
  grep -q "$tok" .loops/haip-config.md
done
test -s .loops/haip-probe-terra.log
test -s .loops/haip-probe-luna.log
if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  ! grep -rqF "$ANTHROPIC_AUTH_TOKEN" . 2>/dev/null
fi

# D3
! grep -rq claude-fable-5 .claude/
for h in '## The loop' '## The nine rules' '## Routing' 'Output style' 'Engineering principles'; do
  grep -q "$h" .claude/CLAUDE.md
done
grep -qE 'Bash|cannot inspect binaries' .claude/agents/explorer.md
grep -qE 'Write|cannot persist files' .claude/agents/planner.md

# criterion 12 — numeric line-count assertion, not just a bare print
lc=$(wc -l < .claude/CLAUDE.md)
[ "$lc" -le 130 ]

# D4 — criteria 19/20: each agent's model: field must match its own proof
# outcome recorded in haip-config.md, not just assumed.
if awk '/\*\*luna/,/PROPOSED-NOT-VERIFIED\.$/' .loops/haip-config.md | tr '\n' ' ' | grep -q 'haip-builder-observed\.log`* *PASSED'; then
  grep -q '^model: gpt-5.6-luna-mantle$' .claude/agents/builder.md
else
  grep -q '^model: sonnet$' .claude/agents/builder.md
  grep -q 'PROPOSED-NOT-VERIFIED' .loops/haip-config.md
fi

if awk '/\*\*terra/,/PROPOSED-NOT-VERIFIED\.$/' .loops/haip-config.md | tr '\n' ' ' | grep -q 'haip-evaluator-observed\.log`* *PASSED'; then
  grep -q '^model: gpt-5.6-terra-mantle$' .claude/agents/evaluator.md
else
  grep -q '^model: sonnet$' .claude/agents/evaluator.md
  grep -q 'PROPOSED-NOT-VERIFIED' .loops/haip-config.md
fi

# criterion 21 — explorer keeps a stated model tier, and the luna-vs-haiku
# cost tradeoff is recorded (not silently decided) in haip-config.md.
grep -qE '^model: [a-zA-Z0-9._-]+$' .claude/agents/explorer.md
grep -qF '$0.20/$1.20 vs $1/$5' .loops/haip-config.md

# both observed logs must show at least one tool_use paired with a tool_result
# — a prose-only transcript with no matching tool_result fails this gate.
for f in .loops/haip-builder-observed.log .loops/haip-evaluator-observed.log; do
  tu=$(grep -c '"type":"tool_use"' "$f")
  tr=$(grep -c '"type":"tool_result"' "$f")
  [ "$tu" -ge 1 ]
  [ "$tr" -ge 1 ]
done

# criteria the script cannot mechanically grade — evaluator must judge these
# by reading, not assume pass because the script stayed silent.
echo "EVALUATOR-JUDGEMENT-REQUIRED: criterion 4 (SKILL.md sha256 + disable-model-invocation intact) not mechanically checked here"
echo "EVALUATOR-JUDGEMENT-REQUIRED: criterion 5 (CLAUDE.md 99-130 byte-identical to pre-build snapshot) not mechanically checked here"
echo "EVALUATOR-JUDGEMENT-REQUIRED: criterion 10 (Risk-1 gate: no tier reassignment without observed tool-using run) not mechanically checked here"
echo "EVALUATOR-JUDGEMENT-REQUIRED: criterion 14 (CLAUDE.md 99-130 byte-identical to pre-build snapshot, D3 gate) not mechanically checked here"
echo "EVALUATOR-JUDGEMENT-REQUIRED: criterion 15 (git diff --name-only touches only files named in Constraints, .loops/ carve-out applies) not mechanically checked here"
echo "EVALUATOR-JUDGEMENT-REQUIRED: criterion 18 (proof task log actually shows declared-tool invocation, not merely text) not mechanically checked here"

echo VERIFY_OK
