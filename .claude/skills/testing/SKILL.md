---
name: testing
description: Write and run tests that actually prove behavior — unit and browser/e2e. Use when adding tests, or when a change needs test coverage before it can be accepted. Favors tests that would fail if the behavior regressed.
---

# testing

> A test that can't fail proves nothing. Write the test you'd trust to catch the
> regression, then confirm it fails without the fix and passes with it.

## Principles

- **Test behavior, not implementation.** Assert on observable outputs and effects,
  not internal calls — so refactors don't break green tests.
- **Red first.** For a bug fix, write the failing test first; watch it fail; then
  fix; watch it pass. That's proof the test is load-bearing.
- **One reason to fail per test.** Clear names that state the expected behavior.
- **Deterministic.** No reliance on wall-clock, network, or ordering. Seed randomness.

## Unit

- Cover the contract's acceptance criteria that are unit-checkable.
- Include the edge and failure cases, not just the happy path — empty input,
  boundaries, error propagation.

## Browser / e2e

- Drive the real user flow (playwright/Chrome DevTools MCP): navigate, interact,
  assert on rendered state, check the console for new errors.
- Screenshot before/after for visual changes.
- Run a performance/Core-Web-Vitals pass when the contract cares about it.

## Run and report

- Run the full relevant suite, not just the file you touched.
- Report pass/fail counts honestly. A skipped or xfail'd test is not a passing test —
  say so.

## Do not

- Write tests that assert on mocks of the thing under test.
- Loosen an assertion to make a test pass — fix the code or the expectation, and say which.
- Report green without having run it.
