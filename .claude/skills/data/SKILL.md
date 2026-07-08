---
name: data
description: Data-science work — pandas/dataframes, SQL, and notebooks. Use when transforming, analyzing, or validating data. Encodes the checks that make a data change trustworthy, not just runnable.
---

# data

> A pipeline that "ran" is not a pipeline that's correct. Data work is verified by
> what comes out, not by exit code 0.

## Gather

- Know the source: schema, row count, grain (one row per what?), and how it's
  refreshed. Sample real rows before writing any transform.
- For SQL, read the table definitions; don't assume column semantics from names.

## Act

- Prefer vectorized pandas over loops; prefer set-based SQL over row-by-row.
- Keep transforms pure and composable — each step inspectable in isolation.
- Never mutate the source in place; write to a new frame/table/path.
- In notebooks, keep cells idempotent and ordered so a top-to-bottom re-run reproduces the result.

## Verify (the part that matters)

Run the transform on a real sample and check:
- **Shape** — row count before/after (did a join fan out or drop rows?).
- **Dtypes** — no silent object columns, no unintended float→int.
- **Nulls** — count nulls per key column; a spike means a broken join/merge.
- **Keys** — uniqueness of the grain; no unexpected duplicates.
- **Values** — spot-check specific known rows against expected output.
- **Aggregates** — a sum/mean/count that should be invariant across the transform.

Encode these as assertions in the contract's verify command where possible
(`assert df.shape[0] == ...`, a row-count query, a checksum).

## Do not

- Trust `head()` as verification — it hides tail/edge problems.
- Silently `dropna`/`fillna` without stating why in the log.
- Report a result you couldn't reproduce with a clean re-run.
