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
- **Seam names are a public contract** — `authorize`, `perform`, `mount_mcp`, and the
  notification event. Never rename, alias, or add a synonym; apps and event subscribers
  depend on the exact spelling.
- The notification event has **one canonical name, defined once in code** (see SPEC R4).
  Reference that constant; do not hardcode the string in multiple places.

## Architecture invariants (enforced, not aspirational)

- **The gem ships no policy.** No authorization, audit persistence, identity resolution, or
  tenant logic in `lib/`. If a change adds any of these to the gem it is wrong — it belongs
  in the app-owned `ApplicationMcpTool`. (ADR-0004)
- **Two seams only** — `authorize` and the notification event. Adding a third seam needs an
  ADR.
- **Allow-list only.** The sole callable surface is registered `RailsMcp::Tool` subclasses.
  No generic executor, no console tool, no `eval`, no `rails runner` path. (ADR-0004, R10)
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
