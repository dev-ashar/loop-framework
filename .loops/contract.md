# Contract — explorer Git and gh capability fix

This contract defines the reviewable boundary for the explorer capability repair.
The prior contract is complete and independently passed.
Proceed sequentially in the current worktree.
Do not use a worktree.
Do not modify implementation during contract review.

## Goal

Enable explorer to perform read-only Git research and authenticated `gh` queries.
Route Git and `gh` research to a capable explorer path.
Prevent clearly mutating or outward Git and `gh` commands through the global pre-tool hook.
Keep the controls honest about shell and role limits.

## Constraints

- Use real Claude Code features only.
- Grant explorer direct `Bash` access; do not invent `Bash(ro:*)` or permission signatures.
- Do not add role-aware hook fields; Claude Code hooks cannot identify agent roles reliably.
- Do not claim the hook makes all shell mutations impossible.
- Preserve the current uncommitted contract-gate implementation byte-for-byte outside approved edits.
- Keep planner, builder, evaluator, explorer, and orchestrator responsibilities separate.
- Keep `.loops/log.md` append-only when implementation starts.
- Treat local reports, files, commits, and environment claims as advisory evidence.
- Require fresh capability and authentication checks before dispatch.
- Return `BLOCKED` when a required capability or authentication check fails.
- Reroute only to another capable read-only route; never emit a degraded report.
- Do not add cryptographic signatures or an authentication service.

## Explorer command policy

Explorer may run direct Bash for read-only repository and GitHub research.
Allowed Git commands include:

- `git status --short` and `git status --porcelain=v1`
- `git log`, `git show`, `git diff`, and `git blame` with read-only arguments
- `git branch --list`, `git tag --list`, `git remote -v`, and `git rev-parse`
- `git ls-files`, `git ls-tree`, and `git describe`

Allowed `gh` commands include authenticated read-only queries:

- `gh auth status`
- `gh repo view`
- `gh issue view` and `gh issue list`
- `gh pr view` and `gh pr list`
- `gh run view` and `gh run list`
- `gh api` only for `GET` requests or endpoints whose method is explicitly read-only

Explorer must not run commands that create, delete, rewrite, publish, merge, push, or alter remotes.
Explorer must not use shell redirection, command substitution, pipelines, or helper commands to mutate files.
Explorer must not treat a command as read-only only because its output appears informational.
The policy describes intended commands; the hook remains a best-effort guard for clear mutations.

## Capability and authentication preflight

Before dispatch, inspect the explorer definition and confirm it lists `Bash`.
Run `git --version` and `gh --version` before Git/gh research.
Run `git rev-parse --show-toplevel` and require a successful repository result.
Run `gh auth status` before authenticated GitHub queries.
Treat a missing binary, failed repository check, or failed `gh auth status` as `BLOCKED`.
Reroute only to another route with equivalent read-only Git/gh capability and valid authentication.
Do not substitute unauthenticated scraping, guessed data, or a degraded report.
Record the preflight result and command exit status in the dispatch evidence.

## Global pre-tool hook boundary

Expand `.claude/hooks/pre-tool-use.sh` only for clearly mutating or outward Git/gh operations.
Block clear mutations such as `git commit`, `git push`, `git fetch`, `git pull`, `git merge`, `git rebase`, `git reset`, `git clean`, remote changes, and destructive branch or tag operations.
Block clear outward `gh` operations such as creating, editing, closing, merging, commenting, labeling, deleting, releasing, or dispatching workflows.
Allow read-only Git and authenticated `gh` queries required by explorer.
Use command text matching only where the hook can identify an operation clearly.
State in comments and tests that the hook cannot identify agent roles.
State in comments and tests that arbitrary shell mutations cannot be guaranteed impossible.
Do not broaden the hook into a general shell policy or block unrelated read-only commands.

## Claude Code hook binding

Bind `.claude/settings.json` `PreToolUse` for matcher `Bash` to `$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-use.sh`.
Use the repository path, not `$HOME/.claude/hooks/pre-tool-use.sh`, for this project hook.
Keep the hook command a real Claude Code command hook with no invented permission signature.
Test the binding by parsing `.claude/settings.json` and asserting the exact command string.

## Dispatch requirements

Use the following authoritative route table in `.claude/dispatch.md`.

| Research need | Required route | Preflight | Failure route |
|---|---|---|---|
| Read-only local Git | explorer | Bash, git binary, repository root | equivalent read-only route or BLOCKED |
| Authenticated GitHub query | explorer | Bash, gh binary, repository root, `gh auth status` | equivalent authenticated read-only route or BLOCKED |
| Git/gh research without explorer Bash | no full-Bash fallback | capability check | equivalent read-only route or BLOCKED |

Route Git or `gh` research to `explorer` when its capability preflight passes.
Require the dispatch record to name the selected route, preflight commands, and authentication result.
When explorer lacks `Bash`, return `BLOCKED` and reroute only to an equivalent capable read-only route.
When `gh auth status` fails, return `BLOCKED` and reroute only to an equivalent authenticated route.
If no equivalent read-only route exists, return `BLOCKED`.
Never use full-Bash `general-purpose` as a degraded fallback.
Never dispatch Git/gh research to a route that cannot run the required read-only commands.
Never report partial, guessed, unauthenticated, or degraded research as complete.
Do not claim that a hook field identifies the active agent role.

## Explorer preflight and result schema

Record one result for every explorer dispatch using this exact field schema:

```text
EXPLORER_PREFLIGHT:
  route: explorer
  command: <exact command>
  exit: <decimal status>
  status: COMPLETE|BLOCKED|REROUTE
  detail: <bounded reason or result>
```

Use one `EXPLORER_PREFLIGHT` block per command, in execution order.
Set `status=COMPLETE` only after every required preflight and research command succeeds.
Set `status=REROUTE` only when an equivalent read-only route is selected and recorded.
Set `status=BLOCKED` when no equivalent route exists or authentication fails.
Do not emit a completion report for `BLOCKED` or `REROUTE` without the selected equivalent route.
Do not emit degraded completion under any status.
Record actual Agent explorer dispatch evidence with the dispatch identifier and final schema block.
If dispatch is unavailable, record `EXPLORER_DISPATCH: unavailable reason=<bounded reason>` and status `BLOCKED`.

## Approval and review UX

Generate the approval presentation with exact commands before dispatch:

```bash
approval=$(mktemp)
trap 'rm -f "$approval"' EXIT
repo_root=$(git rev-parse --show-toplevel)
contract_hash=$(sha256sum "$repo_root/.loops/contract.md" | awk '{print $1}')
printf '%s\n' \
  'Contract summary:' \
  '- Goal: enable explorer read-only Git and authenticated gh research.' \
  '- Behavior: bind the repository hook and block clear Git and gh mutations.' \
  '- Verification: run hook fixtures, dispatch checks, and the full verifier.' \
  'Contract path: .loops/contract.md' \
  'Review command: git diff -- .loops/contract.md' \
  "Contract SHA-256: $contract_hash" \
  'APPROVAL: pending host review' >> "$approval"
printf '%s\n' "Pre-approval file: $approval"
```

Check the pre-approval presentation with explicit static fields and commands.
Require `grep -Fx 'Contract path: .loops/contract.md' "$approval"` to pass.
Require `grep -Fx 'Review command: git diff -- .loops/contract.md' "$approval"` to pass.
Require `grep -Fq "Contract SHA-256: $contract_hash" "$approval"` to pass.
Require `grep -Fx 'APPROVAL: pending host review' "$approval"` to pass.
Do not generate or structurally validate `APPROVAL: host-confirmed` before host response.
After explicit host approval, the orchestrator must replace the pending line with this exact record:

```text
APPROVAL: host-confirmed repoRoot=<repo_root> contractHash=<contract_hash> runId=explorer-readonly-git correlationId=52ac91ef role=builder
```

Immediately before builder dispatch, invoke:

```bash
bash .loops/verify.sh approval-request "$approval" --run explorer-readonly-git --correlation 52ac91ef --role builder
```

Require the validator to pass and record its exact exit status.
Host approval remains pending until the host explicitly approves the exact presentation.
Every approval request must present a bounded readable summary with 1-5 bullets.
Each summary bullet must contain at most 20 words.
The summary must cover the goal, behavior changes, and verification boundary.
Every request must show the exact contract path `.loops/contract.md`.
Every request must show `git diff -- .loops/contract.md` or an equivalent exact review command.
Every request must show the exact active contract SHA-256.
A bare hash, local file, report, commit, or environment value is not approval.

## Task allowlist

The task-attributable delta only must be a subset of this task allowlist:

- `.claude/agents/explorer.md`
- `.claude/dispatch.md`
- `.claude/hooks/pre-tool-use.sh`
- `.claude/settings.json` only when required for the real Claude Code feature
- `tests/` files needed for behavioral hook or dispatch tests
- `.loops/contract.md`
- `.loops/log.md` for one append-only implementation entry

Frozen non-task paths may remain changed relative to HEAD, but they must match captured pre-build hashes.
The current uncommitted contract-gate implementation is outside this repair scope and must remain unchanged.

## Baseline and regression boundary

Freeze the preexisting diff before implementation with this executable manifest command:

```bash
baseline=$(mktemp /tmp/explorer-git-gh-preexisting.XXXXXX)
git diff --name-only -z | while IFS= read -r -d '' path; do
  [ "$path" = .loops/log.md ] && continue
  sha256sum -- "$path"
done > "$baseline"
log_prefix=$(mktemp /tmp/explorer-git-gh-log-prefix.XXXXXX)
cp .loops/log.md "$log_prefix"
printf '%s\n' "$baseline" "$log_prefix"
```

The manifest must contain each currently changed path except `.loops/log.md` and its exact working-tree SHA-256.
Freeze the pre-build `.loops/log.md` prefix or digest instead of byte-freezing the whole log.
Do not count earlier passed contract-gate changes as this task's output.
After implementation, compute task-attributable paths instead of treating raw `git diff --name-only` as the task delta:

```bash
current=$(mktemp /tmp/explorer-git-gh-current.XXXXXX)
git diff --name-only -z | while IFS= read -r -d '' path; do
  [ "$path" = .loops/log.md ] && continue
  printf '%s\n' "$path"
done | sort -u > "$current"
frozen=$(mktemp /tmp/explorer-git-gh-frozen-paths.XXXXXX)
cut -d' ' -f3- "$baseline" | sort -u > "$frozen"
comm -23 "$current" "$frozen" > /tmp/explorer-git-gh-new-paths
: > /tmp/explorer-git-gh-changed-overlaps
while IFS='  ' read -r old_hash path; do
  [ -z "$path" ] && continue
  current_hash=$(sha256sum -- "$path" | awk '{print $1}')
  if [ "$current_hash" != "$old_hash" ] && grep -Fxq "$path" "$current"; then
    printf '%s\n' "$path" >> /tmp/explorer-git-gh-changed-overlaps
  fi
done < "$baseline"
cat /tmp/explorer-git-gh-changed-overlaps /tmp/explorer-git-gh-new-paths | sort -u > /tmp/explorer-git-gh-task-delta
```

Require `/tmp/explorer-git-gh-task-delta` to be a subset of the named task allowlist.
Allow frozen preexisting paths to remain changed relative to HEAD when their captured hashes remain unchanged.
For frozen paths outside the task allowlist, require the captured hash to match `sha256sum -- "$path"`.
For paths in both the frozen manifest and task allowlist, use the captured hash as the base and permit task changes.
Reject any frozen path outside the task allowlist whose captured hash changes.
Check `.loops/log.md` with `git diff --numstat -- .loops/log.md`; require zero deletions and exactly one task-specific final note appended after the frozen prefix.
Permit the task-attributable delta only when it is a subset of the named task allowlist.
Do not treat unbuilt settings, explorer, dispatch, hook, or test state as readiness failures.
Label those files as post-build targets until implementation starts.
Run `bash tests/run_tests.sh` and save live output before implementation.
The baseline is 35/37 passing with exactly two failures.
Criterion 14 has the stable signature `[FAIL] criterion 14:  expected 3 hooks got 5`.
Criterion 21 has the stable signature `[FAIL] criterion 21:  lesson-check-missing`.
Do not treat these two baseline failures as newly introduced.
Do not introduce any additional failure.
The baseline evidence must come from a live run, not a generated or ignored artifact.

## Acceptance criteria

1. `.claude/agents/explorer.md` grants direct `Bash` using real Claude Code configuration.
2. Explorer documentation lists the allowed read-only Git commands.
3. Explorer documentation lists authenticated read-only `gh` query commands.
4. Explorer documentation prohibits Git and `gh` mutations, publication, and remote changes.
5. Explorer performs Git, binary, repository, and `gh auth status` preflight before dispatch.
6. Missing Git, missing `gh`, invalid repository state, or missing `gh` authentication returns `BLOCKED`.
7. Missing explorer capability reroutes only to an equivalent capable read-only route.
8. Missing authentication reroutes only to another authenticated read-only route.
9. Dispatch never emits degraded, guessed, unauthenticated, or partial research as complete.
10. `.claude/settings.json` binds `PreToolUse` Bash to `$CLAUDE_PROJECT_DIR/.claude/hooks/pre-tool-use.sh`.
11. The pre-tool hook blocks clearly mutating Git operations.
12. The pre-tool hook blocks clearly outward or mutating `gh` operations.
13. The pre-tool hook permits required read-only Git and authenticated `gh` queries.
14. Hook fixtures allow `git status --short` and `git log -1` with token `ALLOW_READONLY`.
15. Hook fixtures block `git commit -m fixture` and `git push origin HEAD` with token `BLOCK_MUTATION`.
16. Hook fixtures allow `gh pr view 1` and `gh api repos/o/r` with token `ALLOW_READONLY`.
17. Hook fixtures block `gh pr create --title fixture --body fixture` and `gh issue close 1` with token `BLOCK_OUTWARD`.
18. Hook comments state that hooks cannot identify agent roles.
19. Hook comments state that hooks cannot guarantee every shell mutation is impossible.
20. Hook tests cover blocked Git mutations and allowed Git reads.
21. Hook tests cover blocked outward `gh` operations and allowed read-only `gh` queries.
22. Tests cover missing explorer Bash capability and missing `gh` authentication.
23. Tests perform an actual explorer dispatch check when the environment permits it.
24. Tests use temporary fixtures and clean them with a trap.
25. Tests do not invent Bash permission syntax, signatures, or role-aware hook fields.
26. Post-build task delta includes changed frozen paths in the task allowlist when their hashes differ from captured hashes.
27. Post-build new paths equal current changed paths minus frozen manifest paths.
28. Post-build task delta is the union of changed allowlisted overlaps and new paths.
29. Post-build task delta is a subset of the named task allowlist.
30. Frozen preexisting paths outside the task allowlist retain their captured hashes.
31. The task-attributable delta only is a subset of the exact task allowlist.
32. The baseline remains 35/37 with only criteria 14 and 21 failing before implementation.
33. Every approval request includes 1-5 bullets with at most 20 words each.
34. Every approval request includes the goal, behavior changes, and verification boundary.
35. Every approval request includes the exact contract path and exact review command.
36. Every approval request includes the exact active contract SHA-256.
37. Pre-approval checks use explicit static fields and commands, not `approval-request`.
38. Pre-approval presentation ends with `APPROVAL: pending host review`.
39. After host approval, `approval-request` validates the exact host-confirmed record immediately before builder dispatch.
40. Post-build verification records the actual explorer dispatch result or a bounded infeasibility reason.
41. Post-build verification records every capability and authentication preflight exit status.
42. Post-build comparison rejects changed frozen preexisting paths outside the task allowlist.
43. Post-build comparison permits only named task paths beyond the frozen manifest.

## Required regression tests

Behaviorally test the hook with clear mutating Git commands and read-only Git commands.
Behaviorally test the hook with clear outward `gh` commands and read-only authenticated query commands.
Test blocked dispatch when explorer lacks direct `Bash`.
Test blocked dispatch when `gh auth status` fails.
Test rerouting only to an equivalent capable read-only route.
Test that a degraded route cannot produce a success report.
Run an actual explorer dispatch check when tools and authentication permit it.
If the actual dispatch check is infeasible, record the exact bounded reason and preserve the blocked result.
Assert diagnostic tokens and exit statuses for every case.
Do not claim cryptographic authentication or complete shell confinement.

## Verify

The evaluator must run each post-build command independently.

```bash
bash run.sh lint .loops/contract.md
```

## Post-build commands

Run contract lint:

```bash
bash run.sh lint .loops/contract.md
```

Expected status: exit 0.
Expected output: no lint diagnostics.

Run the baseline and regression suite:

```bash
bash tests/run_tests.sh
```

Expected status: at least 35/37.
Expected failures: only criteria 14 and 21 with the signatures above.

Run the dispatch and hook regression tests:

```bash
bash tests/contract-negotiation.sh
```

Expected status: exit 0.
Expected output: `NEGOTIATION_OK` or the test script's documented success token.

Run approval validation before dispatch:

```bash
approval=$(mktemp)
trap 'rm -f "$approval"' EXIT
repo_root=$(git rev-parse --show-toplevel)
contract_hash=$(sha256sum "$repo_root/.loops/contract.md" | awk '{print $1}')
printf '%s\n' \
  'Contract summary:' \
  '- Goal: enable explorer read-only Git and authenticated gh research.' \
  '- Behavior: bind the repository hook and block clear Git and gh mutations.' \
  '- Verification: run hook fixtures, dispatch checks, and the full verifier.' \
  'Contract path: .loops/contract.md' \
  'Review command: git diff -- .loops/contract.md' \
  "Contract SHA-256: $contract_hash" \
  "APPROVAL: host-confirmed repoRoot=$repo_root contractHash=$contract_hash runId=explorer-readonly-git correlationId=52ac91ef role=builder" > "$approval"
bash .loops/verify.sh approval-request "$approval" --run explorer-readonly-git --correlation 52ac91ef --role builder
```

Expected status: exit 0 for a complete readable approval request.
Structural validation does not approve the host request.
Delete the temporary approval file after validation.

Run the actual explorer dispatch when available:

```bash
# Record Agent dispatch evidence and EXPLORER_PREFLIGHT blocks in the test output.
```

If unavailable, record `EXPLORER_DISPATCH: unavailable reason=<bounded reason>` and `status: BLOCKED`.
Do not replace unavailable dispatch with a general-purpose full-Bash route.

Run full verification:

```bash
bash .loops/verify.sh
```

Expected status: exit 0.
Expected output: `VERIFY_OK`.

Check whitespace in the task and preexisting files:

```bash
git diff --check
```

Expected status: exit 0.
This command checks whitespace only. It does not enforce scope.
The evaluator must rerun every command independently.
