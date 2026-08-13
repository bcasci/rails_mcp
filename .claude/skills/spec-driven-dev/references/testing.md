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

**The fake/real line is the gem/app ownership line.** Gem internals and the official `mcp`
gem are ALWAYS real. App-owned seams the gem doesn't ship — the staff user,
`ApplicationMcpTool`, tenant — may be faked, and only there.

- **Default: real, sociable tests.** Real tool subclasses, the real registry, the real
  fail-closed `authorize`, a real `ActiveSupport::Notifications` subscription. Build objects
  with test builders — never stub a class's own accessor (build a real `input_schema`; don't
  stub `#input_schema`). A solitary test with doubles is a justified exception, named as such.
- **Assert outcomes by default; interaction assertions are a scalpel, not banned.** Prefer
  asserting state (the returned result, the payload, the denial). Assert that something was
  called/emitted only when there is no observable post-state:
  - the notification is fire-and-forget — assert it fired **exactly once** with the right
    payload on success and **not at all** on denial (`assert_equal 0, events.size`).
    Subscribe via `ActiveSupport::Notifications.subscribed(handler, "invoke.rails_mcp") { … }`
    so it auto-unsubscribes (a bare `subscribe` leaks across tests and double-counts). Target
    Rails 7.1 — hand-roll this; `assert_notification`/`capture_notifications` are Rails 8.0+.
  - command ordering — `authorize` runs before `perform`, and `perform` never runs on deny.
- **Never mock the unit under test or the gem's own classes.** Args DSL → real tool. Invoke
  pipeline → run it for real.
- **The `mcp` gem is real — never stub what it returns, at any level. Two real entry points:**
  - **Unit (T1/T5):** drive a real `MCP::Server` in-process with
    `server.handle(request_hash, session: nil)` / `#handle_json` — real JSON-RPC, no HTTP.
    Use for the registry/allow-list (`tools/list` returns only registered tools; an
    unregistered `tools/call` is refused).
  - **Integration (T7):** mount the real `StreamableHTTPTransport` Rack app at `/mcp` and make
    real MCP calls (`Rack::Test`, or `ActionDispatch::IntegrationTest` against the dummy app).
- **App-side fakes are allowed at the ownership boundary — and only there.** The gem ships no
  staff user, `ApplicationMcpTool`, or tenant, so a plain fake is the correct "boundary you
  don't own." Permitted: a **fake staff user** (object carrying the attributes `authorize`
  and the R4 payload read), a **fake tenant** (R11 cross-tenant denial lives in the dummy
  app's wiring, never gem code), the dummy app's **stub `ApplicationMcpTool`**. Each fake MUST
  honor the real contract: `authorize(user:, args:, tool:)`, a `user` shaped as the payload
  expects.
- **Control time and randomness by injecting a clock/RNG seam** (defaulting to the real one)
  and freezing it, or Rails' real `travel_to` — not by mocking domain logic. This makes the
  outcome deterministic; it stays a state assertion.
- **Error paths: forcing a real, documented failure is allowed.** Making a boundary raise its
  real error (`Timeout::Error`, the `mcp` gem's own error types) to test fail-closed honors
  the contract. Only inventing a *success* shape the real method never returns is forbidden.
- **MANDATORY contract test.** Every fake/stub of a surface you don't own (the `mcp` gem
  especially) is paired with a real-transport integration test (T7) on the same path. A
  double without its contract test is an incomplete test, not a passing one.
- **Tells to avoid:** `Minitest::Mock#expect`/`verify` or pulling in mocha/rr where a real
  object, a plain fake, or `Object#stub` would do; stubbing a method to return a shape the
  real method never produces; an all-mocks suite with no integration test; a side effect
  verified only by downstream state, missing the "fired exactly once / not on deny" assertion.

**Test-dependency precondition:** T7's real mount needs `rack-test` (and `rails` for
`ActionDispatch::IntegrationTest`) plus the real `mcp` gem in the test group — declared in the
gemspec dev deps. Without them these rules are aspirational.

## Mandatory security/fail-closed tests where relevant

- Default `authorize` denies (R3).
- Exactly one notification per invoke, success or failure; no credential in the payload (R4).
- The registry refuses an unregistered tool; no arbitrary-Ruby/console surface (R10).
- A missing required arg and a wrong-typed arg are rejected before `perform` (R1).
