# SPEC — opt-out seams for tool creation and exposing

Build contract for spec 0004: make every convenience in tool creation and tool exposing
peel back to a raw `mcp` primitive, per ADR-0007 — so an app can get specific without leaving
the gem, and no ergonomic default is a cage. Builds on shipped specs 0001–0003 (archived).
Requirements are testable; acceptance criteria are Given/When/Then.

All decisions are settled — `DECIDED` marks each. No `OPEN:` forks remain; the build runs
unattended. Governing decision: **ADR-0007** (convenience without lock-in). Unchanged and in
force: ADR-0004 (zero policy), ADR-0005 (identity), ADR-0008 (controller).

---

## Background

Two conveniences currently lock in rather than default:

- `RailsMcp::Tool` extends `Args`, and `Args#input_schema` (`lib/rails_mcp/args.rb:52`)
  **shadows** the `mcp` gem's `input_schema` macro — so a tool cannot set a raw JSON Schema; it
  must use the `arg` DSL. The annotations mixin needs the same check.
- Registration is central-only (the initializer). There is no co-located option, and the
  registry escapes (a per-endpoint registry, a plain `tools:` array, a raw `MCP::Tool`) work
  but are undocumented and untested as supported seams.

This spec makes the DSL yield to explicitly-set values, adds a co-located `expose!`, and
documents+tests the registry escapes — **document-only, no warnings or blocks** (ADR-0007).

---

## Scope

### In this spec

- `input_schema` / `annotations` on a `RailsMcp::Tool` yield to an explicitly-set value; the
  DSL only builds when it is used.
- `expose!` — an optional, co-located self-registration macro (still explicit per tool).
- Documented+tested registry escapes: a raw `MCP::Tool` (unaudited), a per-endpoint
  `RailsMcp::Registry`, a plain `tools:` array to `MCP::Server`.
- No-auto-discovery guardrail asserted (ADR-0007).

### Explicitly deferred / out of scope

- The controller / entry point — spec 0003.
- Any warning, deprecation, or block when an app opts out — explicitly rejected (ADR-0007):
  the gem documents, it does not nanny.
- Changes to `authorize`, the payload, or identity — frozen.

### Ownership boundary (restated)

The gem is opinionated defaults, not enforcement (ADR-0007). A raw `MCP::Tool` gets no
`authorize`/audit — the app's informed, documented choice. Audit persistence and any
observability beyond the `invoke.rails_mcp` event (e.g. `mcp`'s `around_request`) are the
app's.

**DECIDED** `input_schema` and `annotations` on a `RailsMcp::Tool` **yield to an
explicitly-set value**; the DSL builds only when used.

**DECIDED** `expose!` is added as an optional co-located registration macro; the install
generator's default stays central registration in the initializer.

**DECIDED** a raw `MCP::Tool` registers via the ordinary `register` with **no warning and no
block** (document-only, ADR-0007). No `unaudited:` flag, no `register_raw`.

**DECIDED** no auto-discovery — exposure is always an explicit `register`/`expose!`; the gem
never registers a tool by mere subclassing.

---

## Requirements

### R1 — Raw `input_schema` overrides the DSL

A `RailsMcp::Tool` that sets `input_schema` explicitly uses that schema; the `arg` DSL builds
the schema only when `arg` is used. The two never fight.

- **Given** a tool that calls the `mcp` `input_schema(properties:, required:)` macro and no
  `arg`, **when** the server advertises it, **then** the advertised input schema is the
  explicitly-set one (not an empty DSL-built schema).
- **Given** a tool that uses `arg` and does not set `input_schema`, **when** advertised, **then**
  the schema is built from the declared args exactly as spec 0001 R1 froze.
- **Given** a tool that both uses `arg` and sets a raw `input_schema`, **when** advertised,
  **then** the explicitly-set schema wins (the explicit value is the escape hatch), and this
  precedence is documented.

### R2 — Raw `annotations` overrides `read_only!`

- **Given** a tool that sets `annotations(...)` directly, **when** advertised, **then** those
  annotations are emitted (the DSL yields to the explicit value).
- **Given** a tool that calls `read_only!` and does not set annotations, **when** advertised,
  **then** it carries `readOnlyHint: true` exactly as spec 0001 R5 froze.

**BUILD-TIME CHECK** (not a decision) the builder confirms whether the annotations mixin
shadows the `mcp` `annotations` macro the way `Args#input_schema` does; if so, apply the same
yield-to-explicit fix; if not, add only the covering test.

### R3 — `expose!` co-located registration

An optional class macro registers the tool to the default registry from inside the class —
explicit, idempotent, no auto-discovery.

- **Given** a tool that calls `expose!`, **when** the app boots (or the class loads), **then**
  the tool is on `RailsMcp.registry` and is listable/callable — with no initializer entry for
  it.
- **Given** `expose!` called twice (e.g. reload), **when** the registry is read, **then** the
  tool appears once (idempotent, like `register`).
- **Given** the install generator, **when** it runs, **then** its default still registers the
  example tool centrally in the initializer (spec 0001 R8) — `expose!` is an alternative, not
  the new default.

### R4 — Registry escapes are supported, tested seams

- **Given** a raw `MCP::Tool` subclass (not a `RailsMcp::Tool`), **when** registered via the
  ordinary `register` and invoked, **then** it runs and is listable — with **no** `authorize`
  or `invoke.rails_mcp` event (it is outside the gem's pipeline), and **no** warning or error
  from the gem. This is documented as the app's informed choice (ADR-0007).
- **Given** a per-endpoint `RailsMcp::Registry.new` distinct from `RailsMcp.registry`, **when**
  its tools are served, **then** only that registry's tools are listable/callable.
- **Given** a plain `tools: [...]` array passed straight to `MCP::Server`, **when** served,
  **then** it works without `RailsMcp.registry` at all (the registry is a convenience, not a
  requirement).

### R5 — No auto-discovery (guardrail)

- **Given** a `RailsMcp::Tool` subclass that is defined but never `register`ed or `expose!`d,
  **when** the registry is read, **then** it is **absent** — the gem does not auto-register by
  subclassing.
- **Given** the gem source, **when** audited, **then** there is no `inherited`-hook or
  convention that adds tools to a registry automatically.

---

## Non-goals (guardrails)

- No warning, deprecation, or block on any opt-out (ADR-0007) — document only.
- No auto-discovery of tools (R5, ADR-0007).
- No change to `authorize`, the `invoke.rails_mcp` payload, identity, or the controller
  (specs 0001/0003; ADR-0005/0008).
- No gem-side audit persistence or policy (ADR-0004).
