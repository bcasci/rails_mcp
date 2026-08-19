# Conventions — `rails_mcp`

Project-specific rules only. General Ruby/gem/Rails idioms (frozen string literals,
semver, minitest layout, standardrb style) are assumed known and are not repeated here.
Imperative and enforced. Authoritative values live in code — this doc points, it doesn't
duplicate.

## Naming — name things what they are

- **Tools** are named for the action they expose, in the app's domain vocabulary:
  `Households::LookupTool`, not `Tool1` or `DataTool`. A reviewer reading the class name
  must know exactly what the AI can do.
- **Args** are named for the domain concept: `arg :household_id`, never `arg :id` or
  `arg :param`. The arg name is what the AI sees in the schema — it must be self-describing.
- **Seam names are a public contract** — `authorize`, `perform`, and the `invoke.rails_mcp`
  notification event. Never rename, alias, or add a synonym; apps and event subscribers
  depend on the exact spelling.
- The notification event has **one canonical name, defined once in code** (see SPEC R4).
  Reference that constant; do not hardcode the string in multiple places.

## Architecture invariants (enforced, not aspirational)

- **The gem ships no policy.** No authorization, audit persistence, or identity resolution
  in `lib/`. If a change adds any of these to the gem it is wrong — it belongs
  in the app-owned `ApplicationMcpTool`. (ADR-0004)
- **Two seams only** — `authorize` and the notification event. Adding a third seam needs an
  ADR.
- **Allow-list only.** The sole callable surface is the `RailsMcp::Tool` subclasses the app
  lists in `RegisteredTools.all` and hands `MCP::Server.new(tools:)`. No generic executor, no
  console tool, no `eval`, no `rails runner` path. The allow-list guarantee is the `mcp`
  gem's — the array passed to `tools:` is the allow-list. (ADR-0004, ADR-0013, R10)
- **Delegate the protocol** to the official `mcp` gem. No hand-rolled JSON-RPC or transport.
  (ADR-0001)
- **Defaults fail closed.** An unconfigured `authorize` denies rather than allows. (R3)

## Layout

- Public entry `lib/rails_mcp.rb` holds requires only. Implementation in
  `lib/rails_mcp/<thing>.rb`, one class/module per file, file path mirrors the constant.
- Generators under `lib/generators/rails_mcp/`, their templates alongside.
- Code the generator stamps **into the app** is app-owned and editable. Code in `lib/` is
  **gem-owned** and semver-guarded — don't blur the line.

## Public API discipline

- The seam signatures — `authorize`'s and `perform`'s keyword args, the event payload keys —
  are **frozen contracts**. Change them only through a deprecation cycle, never a silent
  break.
- Anything not intended as public API lives under an internal module or is marked
  `@api private`.

## Tests

- One behavior per test. Mirror SPEC acceptance criteria: Given/When/Then maps to
  arrange/act/assert, one requirement's criterion per test.
- **Real objects by default.** Stubs and mocks are for true external boundaries only (network,
  clock, randomness) and must earn their place; never mock the unit under test or the gem's
  own classes, and assert on outcomes, not on "a method was called." Full discipline in the
  `spec-driven-dev` skill's `references/testing.md`.

## Integration reality (this gem is a library over Rails)

The gem's real failures live in the seam between it and a running app — dev reload, production
`Host`, `ApplicationController` middleware — where the gem's own unit
tests don't reach. Build and spec for that seam; don't leave it for review to catch.

- **Test the artifact, not a copy.** An integration test loads the actual generated/stamped
  output (rendered `.tt` templates), never a hand-mirrored or stubbed stand-in. If a test must
  *add* something to pass (an `allowed_hosts`, a header) or *swap* a base class
  (`ActionController::Base` for the app's real `ApplicationController`), that delta is a
  **product finding** — the divergence hides the bug it claims to cover.
- **Exercise the host framework's real defaults.** A real `ApplicationController` (CSRF,
  inherited `before_action`s), a Zeitwerk reload cycle, and a production `Host` header. Bare
  base classes hide exactly the integration failures that ship. (See
  `test/integration/fixture_app/` — the verbatim template fixture — as the pattern.)
- **Write integration-hazard criteria before coding.** For any spec on the gem↔app seam, add
  acceptance criteria for: dev reload (Zeitwerk), cold boot, production host/proxy, and
  host-framework middleware. "The tests are green"
  is necessary, not sufficient — a concern with no criterion is invisible to review.
