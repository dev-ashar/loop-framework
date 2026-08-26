---
name: job-framework
description: Build a small role graph for work that benefits from explicit dependencies.
---

# Job framework

Use this skill only when explicit dependencies improve a multi-part task.

1. Use `explorer` when unknown code needs read-only mapping.
2. Ask `architect` for separate assignments when boundaries are unclear.
3. Create independent `worker` jobs with explicit `writeScope` and `verify` values.
4. Run decorrelated `reviewer` jobs against completed work.
5. Add a `merge` job only when approved parallel branches need integration.

Use `templates/job-profiles.json` to select role models.
Use `templates/job-dag.schema.json` to validate the job graph.
Do not force a DAG for one scoped change.
Do not require envelopes, traces, correlation identifiers, or fixed gate sequences.
Stop on unresolved conflicts, blocked checks, destructive work, outward actions, or a changed goal.
