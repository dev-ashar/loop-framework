---
name: job-framework
description: Build a small role graph for work that benefits from explicit dependencies.
---

# Job framework

Use this skill only when explicit dependencies improve a multi-part task.

1. Use `explorer` when unknown code needs read-only mapping.
2. Ask `architect` for separate assignments when boundaries are unclear.
3. Create independent `worker` jobs with explicit `writeScope`, bounded `objective`, and `verify` values.
4. Run fresh, read-only `reviewer` jobs against completed work.
5. Add a `merge` job only when approved parallel branches need integration.

Use `templates/job-profiles.json` as the sole route/model registry and validate its projections before dispatch.
Use `templates/job-dag.schema.json` to validate the job graph.
Do not force a DAG for one scoped change.
Do not require envelopes, traces, correlation identifiers, or fixed gate sequences.

For execution, the optional single-role engine is `omp` from can1357/oh-my-pi.
Full jobs use `lib/job-omp.sh`, which keeps HAIP configuration isolated, validates
terminal stream completion, and executes each job's declared `verify` command.

Stop on unresolved conflicts, blocked checks, destructive work, outward actions, or a changed goal.
