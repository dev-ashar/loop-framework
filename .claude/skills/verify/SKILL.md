---
name: verify
description: Verify a completed change with executed evidence.
---

# Verify

Run the acceptance checks for the change.

1. Read the stated scope and verification command.
2. Run the command and capture its exit status.
3. Inspect changed files for scope and regression exposure.
4. Use a fresh `reviewer` for nontrivial or correctness-critical work.
5. Report passed checks, failed checks, and uncovered areas.

Do not approve work from a diff alone.
Do not require report envelopes, lifecycle traces, or a fixed review ritual.
