# HAIP gateway config (D2)

Access is already configured — no proxy, no install. Two env vars are exported
from `~/.zshenv` and picked up by any shell/tool that inherits the environment:

- `ANTHROPIC_BASE_URL` — HAIP gateway base URL. Redacted host:
  `https://llm***-REDACTED***` (subdomain + host redacted per contract; the
  literal value is never written to this repo).
- `ANTHROPIC_AUTH_TOKEN` — bearer/API-key credential for the gateway. Value
  never written to this repo (hard secret gate, criterion 7).

Both shapes work against the gateway: Anthropic `/v1/messages` (header
`x-api-key: $ANTHROPIC_AUTH_TOKEN`) and OpenAI `/v1/chat/completions` (header
`Authorization: Bearer $ANTHROPIC_AUTH_TOKEN`).

## Confirmed model list

HAIP serves:
- `gpt-5.6-terra-mantle`, `gpt-5.6-luna-mantle`
- `gpt-5.5-mantle`, `gpt-5.5-nano`
- `gpt-5.4-mantle`, `gpt-5.4-nano`
- `gpt-5-mini`
- `claude-opus-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`,
  `claude-sonnet-5`, `claude-haiku-4-5`
- Gemini 3.x flash and flash-lite

**`gpt-5.6-sol` is NOT served.** A live probe against `/v1/messages` returns
HTTP 400: `Invalid model name passed in model=gpt-5.6-sol`. It is recorded as a
platform follow-up (see contract Out of scope), not treated as available.

`claude-fable-5` is likewise not served by HAIP.

Costs per 1M tokens (in/out): Luna $0.20/$1.20 · Terra $2/$12 · Sol $5/$30 ·
Haiku 4.5 $1/$5. Luna is cheaper than Haiku 4.5 on both axes.

## Tier mapping

- **luna (`gpt-5.6-luna-mantle`)** → candidate for `builder`. Cost $0.20/$1.20
  per 1M in/out — cheaper than both Haiku 4.5 and Sonnet. Proof run in
  `.loops/haip-builder-observed.log` PASSED: Read, Read, Edit (targeted
  in-place string replacement on a pre-existing `/tmp` scratch file — no Write
  tool in `--allowedTools`, so the tier could not substitute a rewrite), and
  Bash tool_use blocks each paired with a tool_result. Reassignment verified,
  not PROPOSED-NOT-VERIFIED.
- **terra (`gpt-5.6-terra-mantle`)** → candidate for `evaluator`. Cost $2/$12
  per 1M in/out. Proof run in `.loops/haip-evaluator-observed.log` PASSED: Read
  + Bash tool_use blocks each paired with a tool_result, plus a parsable
  numeric score (0.45) with a named gap. Reassignment verified, not
  PROPOSED-NOT-VERIFIED.
- **Opus remains orchestrator.** Opus-tier thinking (plan, judge, synthesize,
  decide) stays in this session and is never delegated to a subagent, GPT-tier
  or otherwise.
- No mapping entry treats `gpt-5.6-sol` as available.

## Explorer / haiku decision

`explorer` stays on `claude-haiku-4-5` rather than moving to `gpt-5.6-luna-mantle`,
even though luna is cheaper ($0.20/$1.20 vs $1/$5). Reason: explorer's job is
Read/Grep/Glob recon inside the same Claude Code tool-calling loop as the rest
of the roster; the observed HAIP proof for luna in this run only exercises the
*builder*-shaped task (Read/Write/Bash), not repeated fast small-context
Grep/Glob recon under load. Moving explorer without its own dedicated proof run
would violate the Risk-1 gate (criterion 10), so the reassignment is left
PROPOSED-NOT-VERIFIED and the model tier is unchanged.

## Context window

unverified — assume capped at 200k

## Probes (D2, criterion 8)

- `.loops/haip-probe-terra.log` — terra probed on both `/v1/messages` and
  `/v1/chat/completions`, both returned `"ok"`.
- `.loops/haip-probe-luna.log` — luna probed on `/v1/messages`, returned `"ok"`.
