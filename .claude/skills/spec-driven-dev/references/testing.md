# Testing decisions for rails_mcp

Minitest, standardrb style. Tests mirror SPEC acceptance criteria.

## Where a test lives

- Unit test for a gem file `lib/rails_mcp/<x>.rb` → `test/rails_mcp/<x>_test.rb` (mirror the
  `lib/` path, one test file per class/module).
- Generator test → `test/generators/`.
- End-to-end / mounted `/mcp` against a dummy app → `test/integration/`.

## Before adding a test

- Grep `test/` for existing coverage of the behavior. If it exists, extend or strengthen it
  — do not add a duplicate assertion.
- If two tasks would test the same shared behavior, the task that **owns** the file
  (per disjoint ownership in `tasks.md`) holds the test.

## What a good test asserts here

- One behavior per test; assert the SPEC criterion, not the implementation detail.
- Test the contract, not private methods.
- No tautologies (`assert true`), no assertion-free tests, no over-mocking that ends up
  asserting the mock instead of the behavior.
- Failure states are first-class, not afterthoughts.

## Mandatory security/fail-closed tests where relevant

- Default `authorize` denies (R3).
- Exactly one notification per invoke, success or failure; no credential in the payload (R4).
- The registry refuses an unregistered tool; no arbitrary-Ruby/console surface (R10).
- A missing required arg and a wrong-typed arg are rejected before `perform` (R1).
