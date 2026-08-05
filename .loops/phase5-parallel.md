# Phase 5 parallel-builder evidence

## Dispatch

- One dispatch message started both builders concurrently, with native worktree isolation.
- Builder A started first: `.claude/worktrees/agent-a1c89c4fe5ac22849`; allowlist `lib/models.sh`.
- Builder B started second: `.claude/worktrees/agent-a0f88a712a70e85c7`; allowlist `lib/engine.sh`.
- Builder A completed writing its allowed file. Builder B completed normally, but its completion notification did not fire; it appeared stalled for several minutes although it was already done.
- Both builders were scope-checked from the main checkout.

## Worktrees

Command:

```text
git worktree list
```

Verbatim output:

```text
/Users/devashar/Documents/DS/workspace/loops                                            4954598 [feat/phase1-foundations]
/Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a0f88a712a70e85c7  4bfc7fa [worktree-agent-a0f88a712a70e85c7]
/Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a1c89c4fe5ac22849  4bfc7fa [worktree-agent-a1c89c4fe5ac22849]
```

## Positive scope checks

Models worktree command:

```text
./run.sh scope-check /Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a1c89c4fe5ac22849 origin/main lib/models.sh; printf 'exit=%s\n' "$?"
```

Verbatim output:

```text
exit=0
```

Engine worktree command:

```text
./run.sh scope-check /Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a0f88a712a70e85c7 origin/main lib/engine.sh; printf 'exit=%s\n' "$?"
```

Verbatim output:

```text
exit=0
```

## Negative scope check

Prior captured fixture, pasted verbatim from `.loops/evidence/scope-check-negative.txt`:

```text
### POSITIVE: only allowed file present
$ ./run.sh scope-check /tmp/loops-scopecheck-neg origin/main lib/models.sh
exit=0

### NEGATIVE: out-of-allowlist path added
$ echo ... > /tmp/loops-scopecheck-neg/.env.stolen
$ ./run.sh scope-check /tmp/loops-scopecheck-neg origin/main lib/models.sh
.env.stolen
exit=1
```

Independent scratch-worktree case run in this checkout:

```text
./run.sh scope-check /tmp/phase5-scope-negative-87273 origin/main lib/models.sh; rc=$?; printf 'exit=%s\n' "$rc"
```

The scratch worktree contained the intentionally out-of-allowlist path `.loops-outside-allowlist`. Verbatim output:

```text
.loops-outside-allowlist
exit=1
```

Cleanup command:

```text
git worktree remove --force /tmp/phase5-scope-negative-87273; git branch -D phase5-scope-negative-87273; printf 'cleanup_exit=%s\n' "$?"
```

Verbatim output:

```text
Deleted branch phase5-scope-negative-87273 (was 4bfc7fa).
cleanup_exit=0
```

## Merge and run notes

- `lib/models.sh` and `lib/engine.sh` got into the main checkout by copying each file with `cp` from its builder worktree's `lib/` into the main checkout's `lib/`.
- Copy verification command:

```text
shasum -a 256 /Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a1c89c4fe5ac22849/lib/models.sh /Users/devashar/Documents/DS/workspace/loops/lib/models.sh
```

Verbatim output:

```text
06ac66e596694c13c23f5b80a5a55ee00ca5287d6cdaf7d72d2cd8c9ecfbef79  /Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a1c89c4fe5ac22849/lib/models.sh
06ac66e596694c13c23f5b80a5a55ee00ca5287d6cdaf7d72d2cd8c9ecfbef79  /Users/devashar/Documents/DS/workspace/loops/lib/models.sh
```

```text
shasum -a 256 /Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a0f88a712a70e85c7/lib/engine.sh /Users/devashar/Documents/DS/workspace/loops/lib/engine.sh
```

Verbatim output:

```text
d00a11f875812f52dd3f4bbb630dad7563df4baae676b52316202dc59c7861e8  /Users/devashar/Documents/DS/workspace/loops/.claude/worktrees/agent-a0f88a712a70e85c7/lib/engine.sh
d00a11f875812f52dd3f4bbb630dad7563df4baae676b52316202dc59c7861e8  /Users/devashar/Documents/DS/workspace/loops/lib/engine.sh
```

- Models branch zero-ahead check:

```text
git rev-list --count origin/main..worktree-agent-a1c89c4fe5ac22849
```

Verbatim output:

```text
0
```

- Engine branch zero-ahead check:

```text
git rev-list --count origin/main..worktree-agent-a0f88a712a70e85c7
```

Verbatim output:

```text
0
```

- Worktree isolation refused several large verification commands. Exact refusal text observed: `this agent isolated in worktree ... but command too complex verify stays inside worktree; break it into plain, separate commands. Refusing run`
- Another exact refusal text observed: `...this command runs string through source, can't verified stay inside worktree; run command directly instead.` Builders could write in their worktrees but could not behaviorally test there; behavioral verification ran from the main checkout.
- Both builder worktrees branched from `origin/main` at `4bfc7fa`, not the session HEAD. `git show 4bfc7fa:.loops/contract.md` fails because that base has no contract; the builders therefore saw no `.loops/contract.md` and stale `model:` values in `.claude/agents/*.md`.

## What to change next time

- Use a completion notification fallback when a builder appears stalled.
- Dispatch only plain, separate verification commands inside isolated worktrees.
- Base builder worktrees on the session commit containing the contract and current agent configuration.
- Commit or otherwise stage each allowed builder file before running the merge and zero-ahead checks.
