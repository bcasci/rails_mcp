# TASKS — drop `RailsMcp::Registry` for an app-owned tool list

Task breakdown for spec 0009. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0008 (archived). References like `R1` point to this spec's `spec.md`. Governing decision:
ADR-0013.

Every task is `autonomous`. T1–T3 are independent (disjoint files), parallel; T4 (integration
+ ADR status + gate) depends on all three.

---

## Layer 0 — Remove, re-stamp, document (parallel, disjoint files)

### T1 — Remove `RailsMcp::Registry` + `expose!` from the gem
**Owns:**
- `lib/rails_mcp/registry.rb` (DELETE — `RailsMcp::Registry`, `RailsMcp.registry`, `register`,
  `registered?`, `tools`, `clear`, `ToolNameCollision`)
- `lib/rails_mcp.rb` (CHANGED: remove the `rails_mcp/registry` require)
- `lib/rails_mcp/tool.rb` (CHANGED: remove the `expose!` macro added in spec 0004; the invoke
  pipeline, `authorize`, `perform`, `text_response`, `call` are unchanged)
- `test/rails_mcp/registry_test.rb` (DELETE)
- `test/rails_mcp/expose_test.rb` (DELETE)
- `test/rails_mcp/opt_out_seams_test.rb` (CHANGED: drop the per-endpoint-`Registry` and `expose!`
  assertions; KEEP the "raw `MCP::Tool` runs unaudited" and "plain `tools:` array to
  `MCP::Server`" seams — the plain-array path is now the primary model)

**Depends on:** shipped 0001–0008.
**Acceptance (R1, R6):** no registry/`expose!` symbols in `lib/`; `require "rails_mcp"` loads
clean; the invoke pipeline and DSL are untouched.
**Tag:** `autonomous`.

### T2 — Generator: stamp `RegisteredTools`; controller passes it; initializer stops registering
**Owns:**
- `lib/generators/rails_mcp/install/templates/registered_tools.rb.tt` (NEW: an app-owned
  `RegisteredTools` module whose `.all` returns an explicit array of tool classes, seeded with
  `ExampleReadOnlyTool`; commented as the one place listing what the AI may call)
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED: `MCP::Server.new(
  tools: RegisteredTools.all, …)` — resolved per request; every hardening line
  (`skip_forgery_protection`, `allowed_hosts:`, the auth seam) and the public-`mcp` pattern
  unchanged)
- `lib/generators/rails_mcp/install/templates/initializer.rb.tt` (CHANGED: remove the
  `RailsMcp.registry.register(...)` block; keep the audit-subscribe half)
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED: add `create_registered_tools`;
  drop any registry references)
- `test/generators/install_generator_test.rb` (CHANGED: assert `registered_tools.rb` is stamped
  with `RegisteredTools.all` returning an array incl. `ExampleReadOnlyTool`; the controller passes
  `tools: RegisteredTools.all`; the initializer no longer registers; hardening/fail-closed
  assertions kept)

**Depends on:** shipped. Independent of T1/T3 (disjoint files).
**Acceptance (R2, R3):** generator stamps the app-owned list; controller passes it; initializer
audit half intact.
**Tag:** `autonomous`.

### T3 — Docs + version + changelog
**Owns:**
- `README.md`, `docs/USAGE.md`, `docs/SEAMS.md`, `docs/conventions.md`, `docs/generators.md`
  (CHANGED: describe the app-owned `RegisteredTools` list; remove `RailsMcp.registry`/`register`/
  `expose!` guidance; the getting-started recipe registers a tool by adding it to
  `RegisteredTools.all`)
- `lib/rails_mcp/version.rb` (CHANGED: `VERSION = "0.2.0"`)
- `CHANGELOG.md` (CHANGED: a `0.2.0` entry — registry removed, app-owned list, `expose!` removed)

**Depends on:** shipped. Independent of T1/T2 (disjoint files).
**Acceptance (R5):** docs reflect the app-owned list; version 0.2.0; changelog entry present.
**Tag:** `autonomous`.

---

## Layer 1 — Integration proof + ADR status + gate

### T4 — Verbatim-fixture reload proof, ADR-0009 status, full gate
**Owns:**
- `test/integration/fixture_app/boot.rb` and the fixture files (CHANGED: load the new
  `registered_tools.rb.tt` + the updated `mcp_controller.rb.tt` as stamped; drop any registry
  wiring)
- `test/integration/real_world_hardening_test.rb` OR a new
  `test/integration/registered_tools_test.rb` (CHANGED/NEW: end-to-end `tools/list` + `tools/call`
  through the controller with `RegisteredTools.all`; the **reload proof** — a tool referenced by
  `RegisteredTools.all` redefined mid-run builds `MCP::Server` without `ToolNotUnique` and lists
  once)
- `docs/adr/0009-registry-keyed-by-tool-name.md` (CHANGED: `Status:` → "Superseded by ADR-0013
  (2026-08-19)" with a bidirectional link; body immutable)

**Depends on:** T1, T2, T3.
**Acceptance (R4, R6, R7):**
- `bundle exec rake` (minitest + standardrb) is green.
- The fixture exercises the stamped templates verbatim (spec 0005 R6); end-to-end tool call works
  with the app-owned list.
- Reload stand-in builds the server without `ToolNotUnique`.
- `grep` of `lib/` finds no registry/`expose!`/`ToolNameCollision`; ADR-0009 body unchanged except
  its status line; ADR-0013 referenced.

**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0008)
T1 ┐
T2 ┼─→ T4
T3 ┘
```

T1–T3 parallel (disjoint files); T4 gates.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0013 — do not relitigate):**
- Remove `RailsMcp::Registry` + `expose!` + `ToolNameCollision`; the app owns the tool list.
- Generator stamps `app/mcp/registered_tools.rb` (`RegisteredTools.all` → array); controller
  passes `tools: RegisteredTools.all` per request; initializer stops registering (audit stays).
- Allow-list is `mcp`'s; duplicate `tool_name` caught by `mcp`'s `ToolNotUnique`.
- Reload-safe by construction (per-request list); no ADR-0009 machinery.
- Version 0.1.0 → 0.2.0; no deprecation cycle (no consumers).
- ADR-0009 status → superseded by ADR-0013 (body immutable).
- No change to the invoke pipeline, DSL, controller pattern, identity, or fail-closed seams.

No open decisions remain — every task is `autonomous`.
