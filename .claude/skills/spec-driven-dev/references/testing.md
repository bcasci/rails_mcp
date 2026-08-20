# Testing decisions for rails_mcp

Minitest, standardrb style. Tests mirror SPEC acceptance criteria.

## Where a test lives

- Unit test for a gem file `lib/rails_mcp/<x>.rb` → `test/rails_mcp/<x>_test.rb` (mirror the
  `lib/` path, one test file per class/module).
- Generator test → `test/generators/`.
- End-to-end / mounted `/mcp` against a dummy app → `test/integration/`.
- **Name for the unit or seam, never for a posture** (STD-03). A test file and its test class are
  named for the `lib/` path or the seam under test, never for a spec theme, phase, or posture
  word — no `*_hardening_`, `*_end_to_end_`, `real_world_`, `smoke_`, `sanity_`, or
  `neutral_conduit_` names. One seam/behavior area per integration file; split a grab-bag into a
  file per flow rather than a single posture-framed catch-all.
- **Don't test the text of a `.md` doc** (TEST-05). Asserting that prose or marketing sentences
  appear in a `.md` file is a finding — tests assert runtime behavior. A docs test is allowed
  only when it either (a) asserts a literal code token in the doc equals the same token in shipped
  code (a drift guard) or (b) executes an example extracted from the doc and asserts its behavior.

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

## Stubs and mocks — they must earn their place

A mock that doesn't match reality passes while production breaks. Default to REAL objects.
**Fake/real line = the gem/app ownership line:** gem internals and the `mcp` gem are always
real; only app-owned seams the gem doesn't ship (staff user, `ApplicationMcpTool`, tenant)
may be faked.

- **Real, sociable by default.** Real tool subclasses, a real `RegisteredTools.all` allow-list
  array handed to `MCP::Server.new(tools:)`, fail-closed `authorize`, and
  `ActiveSupport::Notifications` subscription. Build objects; don't stub their own accessors
  (build a real `input_schema`, don't stub `#input_schema`).
- **Assert outcomes.** Use an interaction assertion only for a side effect with no post-state:
  the notification fired **exactly once** on success and **zero** on deny (subscribe via
  `ActiveSupport::Notifications.subscribed(handler, "invoke.rails_mcp") { … }` — auto-unsubscribes;
  `assert_notification` is Rails 8+, hand-roll on 7.1); and `authorize`-before-`perform` order.
- **Never mock the unit under test or the gem's own classes.**
- **Use the `mcp` gem for real** — it's in-process, fast, and deterministic, so mocking it
  would only test your guess of its API. Unit (T1/T5): `MCP::Server#handle(hash, session: nil)`
  / `#handle_json`. Integration (T7): mount real `StreamableHTTPTransport` at `/mcp`.
- **Network boundary** (a third-party HTTP service you don't own): stub the wire with WebMock,
  or record real responses with VCR — the right tool, not a violation. ("Don't mock what you
  don't own" forbids mock *expectations* on a third party's Ruby API, not stubbing HTTP; VCR
  replays real recorded responses.) This gem's own suite has none — the `mcp` dependency is
  in-process — so it needs neither; reach for them only if a test you own hits a real service.
- **App-side fakes, only at the boundary,** each honoring the real contract
  (`authorize(user:, args:, tool:)`): fake staff user, fake tenant (cross-tenant denial lives
  in the dummy app, never gem code), stub `ApplicationMcpTool`.
- **Time/RNG:** inject a seam or use `travel_to`, don't mock domain logic.
- **Error paths:** forcing a real error (`Timeout::Error`, the `mcp` gem's error types) is
  allowed; inventing a success shape the real method never returns is not.
- **Every `mcp`-gem stub needs a real-transport T7 test on the same path.**
- **Tells:** `Minitest::Mock#expect`/mocha where a real object or `Object#stub` fits; a stubbed
  shape reality never returns; an all-mocks suite with no integration test.

**Deps:** T7 needs `rack-test` + `rails` + the real `mcp` gem in the test group (T0 declares them).

## Mandatory security/fail-closed tests where relevant

- Default `authorize` denies (R3).
- Exactly one notification per invoke, success or failure; no credential in the payload (R4).
- `MCP::Server` refuses a `tools/call` for an unlisted name — a name not in the
  `RegisteredTools.all` array handed to `MCP::Server.new(tools:)` (the allow-list is `mcp`'s;
  ADR-0013). The served array is the allow-list; test a call for a name outside it is rejected.
- A redefined tool class rebuilds the server without `ToolNotUnique` — reload-safe by
  construction: the per-request list references current, reloaded classes, so re-defining a tool
  and rebuilding `MCP::Server.new(tools: RegisteredTools.all)` raises no `MCP::ToolNotUnique`
  (ADR-0013).
- No arbitrary-Ruby/console surface (R10) — no generic executor, `eval`, or `rails runner` path
  is reachable through the served tools.
- A missing required arg and a wrong-typed arg are rejected before `perform` (R1).
