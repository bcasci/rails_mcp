# SPEC — drop `RailsMcp::Registry` for an app-owned tool list

Build contract for spec 0009: remove the `RailsMcp::Registry` concept (and `expose!`) and have
the app own the list of tools it hands `MCP::Server`, because the allow-list guarantee is the
`mcp` gem's, not the registry's. Builds on shipped specs 0001–0008 (archived). Given/When/Then
acceptance criteria; `DECIDED` marks settled choices.

Governing decision: **ADR-0013** (drop registry for an app-owned list; supersedes ADR-0009 and
the spec-0004 `expose!` decision, and the registry framing of spec 0001 R10). In force: ADR-0012
(neutral conduit), ADR-0008 (public controller pattern), ADR-0005 (identity), ADR-0004 (zero
policy), ADR-0007 (no auto-discovery).

---

## Background

`MCP::Server` enforces the allow-list itself: it stores only the tools passed to `tools:`
(server.rb:174) and refuses any `tools/call` for a name not in that set (server.rb:754-758). So
the array handed to `MCP::Server.new(tools:)` *is* the allow-list. `RailsMcp::Registry` is a
process-wide boot-time accumulator that only holds that array; its reload/collision machinery
(ADR-0009, `ToolNameCollision`, `expose!`) exists to fix hazards its own design created. A plain
app-owned list resolved per request has no such hazard and mirrors `mcp`. This spec removes the
registry in favor of that list.

---

## Scope

### In this spec

- Remove `RailsMcp::Registry` (`RailsMcp.registry`, `register`, `registered?`, `tools`, `clear`,
  `ToolNameCollision`) and the `expose!` macro, and their requires/references in `lib/`.
- The generator stamps an app-owned `RegisteredTools` list; the generated `McpController` passes
  `tools: RegisteredTools.all` (resolved per request) to `MCP::Server.new`; the initializer no
  longer registers tools (audit-subscribe half stays).
- Update docs and the getting-started recipe to the app-owned list; remove registry/`expose!`
  guidance.
- Bump `version.rb` 0.1.0 → 0.2.0; add a CHANGELOG entry.

### Out of scope

- Auto-discovery (rejected, ADR-0007) — the list stays explicit.
- Any change to the invoke pipeline, the args/annotations DSL, the controller public-`mcp`
  pattern, identity on `server_context`, the fail-closed seams, or read/write neutrality — all
  unchanged.

**DECIDED** the app-owned list is `app/mcp/registered_tools.rb` — a module whose `.all` returns
an explicit array of tool classes. The controller passes `tools: RegisteredTools.all` at request
time (naming constants fresh, so it is reload-safe).

**DECIDED** the allow-list guarantee is `mcp`'s and unchanged; a duplicate `tool_name` is caught
by `mcp`'s `ToolNotUnique` at `MCP::Server.new` (no gem-side `ToolNameCollision`).

**DECIDED** breaking public-seam change with no consumers → no deprecation cycle; version
0.1.0 → 0.2.0 (semver 0.x breaking = minor).

**DECIDED** ADR-0009's body is immutable; only its `Status` line changes to "Superseded by
ADR-0013".

---

## Requirements

### R1 — Registry and `expose!` removed from the gem

- **Given** `lib/`, **when** searched, **then** there is no `RailsMcp::Registry`,
  `RailsMcp.registry`, `register`, `registered?`, `ToolNameCollision`, or `expose!` — and
  nothing in `lib/rails_mcp.rb` or `lib/rails_mcp/tool.rb` requires or references them.
- **Given** `require "rails_mcp"`, **when** loaded, **then** it loads cleanly with the registry
  file gone.

### R2 — Generator stamps an app-owned tool list; controller passes it

- **Given** `rails g rails_mcp:install`, **when** it runs, **then** it creates an app-owned
  `app/mcp/registered_tools.rb` defining a `RegisteredTools` module whose `.all` returns an
  explicit array of tool classes (seeded with the example tool), and the generated
  `McpController#handle` passes `tools: RegisteredTools.all` to `MCP::Server.new`.
- **Given** the generated initializer, **when** read, **then** it no longer registers tools; its
  audit-subscribe half is unchanged.
- **Given** the stamped `RegisteredTools`, **when** read, **then** it is app-owned and editable —
  the one place listing what the AI may call (adding a tool = adding a class to the array).

### R3 — Allow-list unchanged (it is `mcp`'s)

- **Given** the mounted endpoint, **when** `tools/list` is requested, **then** only the classes
  in `RegisteredTools.all` are listed.
- **Given** a `tools/call` naming a class not in `RegisteredTools.all`, **when** received, **then**
  it is refused (`mcp`'s "Tool not found").
- **Given** two classes with the same `tool_name` in the list, **when** the server is built,
  **then** `mcp` raises `ToolNotUnique` (the collision is still caught, by `mcp`).

### R4 — Reload-safe by construction (no ADR-0009 machinery)

- **Given** a tool class referenced by `RegisteredTools.all` that is redefined mid-run (a
  Zeitwerk-reload stand-in — a new class object with the same class name and `tool_name`),
  **when** the next request builds `MCP::Server.new(tools: RegisteredTools.all)`, **then** it does
  **not** raise `ToolNotUnique` and lists the tool once — proving the per-request app-owned list
  is reload-safe with no registry keying/collision code.

### R5 — Docs, version, changelog

- **Given** `README.md`, `docs/USAGE.md`, `docs/SEAMS.md`, `docs/conventions.md`, and
  `docs/generators.md`, **when** read, **then** they describe the app-owned `RegisteredTools`
  list and contain no `RailsMcp.registry`/`register`/`expose!` guidance; the getting-started
  recipe registers a tool by adding it to `RegisteredTools.all`.
- **Given** `lib/rails_mcp/version.rb`, **when** read, **then** `VERSION` is `"0.2.0"`.
- **Given** `CHANGELOG.md`, **when** read, **then** a `0.2.0` (or `[Unreleased]` → `0.2.0`) entry
  records the registry removal and the app-owned list.

### R6 — No collateral behavior change; ADR-0009 superseded

- **Given** the suite, **when** run, **then** it is green, and the invoke pipeline
  (`authorize → perform → notify`), the args/annotations DSL, the controller public-`mcp` pattern,
  identity on `server_context`, the fail-closed seams (`authenticate_acting_user!`, `authorize`),
  and read/write neutrality are all unchanged.
- **Given** `docs/adr/0009-registry-keyed-by-tool-name.md`, **when** read, **then** its `Status`
  is "Superseded by ADR-0013" with a link and its body is unchanged.

### R7 — Verbatim-fixture integration (no diverging harness)

- **Given** the install templates, **when** the fixture exercises them, **then** it loads the
  rendered `mcp_controller.rb.tt` and `registered_tools.rb.tt` as stamped (per spec 0005 R6), and
  a real end-to-end `tools/list` + `tools/call` through the controller passes with the app-owned
  list — no simplified or stubbed stand-in.

---

## Non-goals (guardrails)

- No auto-discovery (ADR-0007); the list is explicit.
- No change to the invoke pipeline, DSL, controller pattern, identity, or fail-closed seams (R6).
- No rewrite of an accepted ADR body (only ADR-0009's status line).
- No new gem concept replacing the registry — the list is ordinary app code.
