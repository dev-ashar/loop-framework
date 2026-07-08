---
name: taste
description: Score subjective quality with a calibrated rubric so "good" becomes gradable. Use when the goal is aesthetic or qualitative (a design, a piece of writing, a UI, a report) and there's no single number that captures "done".
---

# taste

> "Taste is gradable if you write it down." The model won't invent taste — it will
> only converge toward the taste you described. The whole game is writing the
> rubric carefully enough that converging toward it is what you actually wanted.

## Protocol

1. **Pick the axes.** Default four, each scored 0–1: **design · originality ·
   craft · functionality.** Swap axes to fit the artifact (e.g. a report might use
   clarity · rigor · insight · usefulness). Assign weights that sum to 1.

2. **Calibrate on references.** Before scoring the work, pin down the scale:
   - Three reference examples you declare **good** (score ≈ 0.8–1.0).
   - Three you declare **slop** (score ≈ 0.0–0.3).
   Calibration is what stops the score from drifting into meaningless praise.

3. **Score the work.** For each axis: a number and one sentence of justification
   grounded in the references. Compute the weighted total.

4. **Write the gap.** One paragraph: the single most important thing between this
   score and 1.0. This paragraph — not the number — is what drives the next iteration.

## Output

```
TASTE: <weighted 0.00–1.00>
  design:        <0–1> — <why, vs references>
  originality:   <0–1> — <why>
  craft:         <0–1> — <why>
  functionality: <0–1> — <why>
GAP: <one paragraph — the highest-leverage improvement>
```

## Use inside loops

Drop the weighted score into `.loops/feature_list.json` as the metric for a native
`/goal` run, or into `.loops/contract.md` as the taste rubric the `evaluator` uses.

## Do not

- Score without references — an uncalibrated rubric converges on flattery.
- Collapse to a single number without the gap paragraph; the paragraph is the signal.
