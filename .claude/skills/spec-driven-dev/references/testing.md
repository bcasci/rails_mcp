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

## Stubs and mocks — sparingly; they must earn their place

Over-mocking is the top way a suite goes green over broken code: a mock that doesn't match
reality passes while production fails. Default to REAL objects and real code paths.

- **Default: no mocks.** Use real tool subclasses, a real `ActiveSupport::Notifications`
  subscription, the real registry, the real fail-closed `authorize`. Assert on OUTCOMES —
  the returned result, the emitted event's payload, the actual denial — never on "a method
  was called."
- **Never mock the unit under test or the gem's own classes.** Testing the args DSL → real
  tool. Testing the invoke pipeline → run it for real.
- **Stub only a true boundary you don't own and can't cheaply run for real** — a third-party
  network call, the clock, randomness. Even then prefer a small real FAKE (a plain object
  implementing the real interface) over a mock that asserts calls. A fake must honor the
  real contract.
- **A stubbed boundary needs a real counterpart test.** If you fake something, an
  integration/contract test must exercise the real thing so drift surfaces. T7 mounts a real
  Rack `/mcp` and makes real MCP calls — never mock the protocol.
- The official `mcp` gem is a real dependency: build a real `input_schema`, mount its real
  transport; don't stub what it returns.
- **Tells to avoid:** asserting an expectation instead of an outcome; stubbing a method to
  return a shape the real method never produces; an all-mocks suite with no integration test.

## Mandatory security/fail-closed tests where relevant

- Default `authorize` denies (R3).
- Exactly one notification per invoke, success or failure; no credential in the payload (R4).
- The registry refuses an unregistered tool; no arbitrary-Ruby/console surface (R10).
- A missing required arg and a wrong-typed arg are rejected before `perform` (R1).
