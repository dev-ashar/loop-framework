---
name: llm-agent
description: Build and evaluate LLM/agent systems on the Claude API — prompts, tools, agent loops, eval harnesses. Use when writing agent code, designing prompts/tools, or building evals. Always check the claude-api reference for current model ids, pricing, and params before writing.
---

# llm-agent

> Two roles, one rule (Karpathy II): the thing that generates output and the thing
> that grades it are never the same context. Evals are how you make that concrete.

## Before writing any LLM code

- Consult the **`claude-api`** reference (or the `claude-api` skill) for current
  model ids, pricing, params, streaming, tool-use, caching, token counting. Never
  answer model questions from memory — they go stale.
- Default to the latest capable models (Opus 4.8 / Sonnet 5 / Haiku 4.5); pick the
  cheapest tier that clears the task's bar, not reflexively the biggest.

## Prompts & tools

- Make the task's success criterion explicit in the prompt — the model converges on
  what you describe, not what you meant.
- Tool schemas: precise descriptions, tight parameter types, and examples of when
  NOT to call. Ambiguous tools are the top cause of bad agent behavior.
- Use prompt caching for stable prefixes; measure token usage rather than guessing.

## Agent loops

- Structure as gather → reason → act → verify → repeat. Keep state on disk, not in
  an ever-growing context (loops rot the window).
- Separate roles into separate contexts: a generator that acts, an evaluator that
  grades against a rubric. Never let the generator grade itself.

## Evals (the part that makes it real)

- Build a dataset with reference-good and reference-slop examples (calibration —
  see the `taste` skill for subjective axes).
- Grade with a deterministic metric where one exists; use an LLM judge only with a
  written rubric, and spot-check the judge against human labels.
- Log every run to a TSV/`feature_list.json`; detect plateaus; treat the eval score
  as the metric for a native `/goal` loop.

## Do not

- Ship prompt/model changes without an eval delta — "it seems better" is not a result.
- Let the agent that produced an answer be the one that scores it.
- Hardcode a model id without checking it's current.
