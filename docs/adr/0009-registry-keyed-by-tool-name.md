# ADR-0009 — Registry keyed by tool name, reload-safe, collision-detecting

Status: Accepted (2026-08-13)

## Context

`RailsMcp::Registry` keyed its allow-list by **class identity** (`@tools[tool_class] = true`)
and never cleared. In development, Zeitwerk reloads a tool file on every edit, producing a
**new class object** with the same `tool_name`; the process-wide `RailsMcp.registry` (memoized
on the never-reloaded gem module) kept the stale class alongside the fresh one. The next MCP
request built `MCP::Server.new(tools: [stale, fresh])`, whose `validate!` raises `ToolNotUnique`
(mcp `server.rb:508`) because two classes advertise the same `tool_name`. Net: **editing any
tool in development breaks the `/mcp` endpoint until the server restarts** — on both the central
`register` path and the co-located `expose!` path. This was not caught because the reload test
re-invoked `expose!` on the *same* class object (idempotent by identity), not a redefined class.

The fix must be reload-safe without swallowing a **genuine collision** — two *different* tool
classes claiming the same `tool_name`, which should still surface rather than silently let the
last one win.

## Decision

`RailsMcp::Registry` keys the allow-list by **`tool_name`**, not class identity.

- `register(tool_class)` stores the class under its `tool_name`.
- Re-registering a class whose `tool_name` is already present, when the incoming class has the
  **same class name** (a Zeitwerk reload — same `Foo::BarTool`, new object), **replaces** the
  stale entry. `tools` therefore never contains two objects sharing a `tool_name`, so
  `MCP::Server` never raises `ToolNotUnique` across reloads.
- Re-registering a **different** class (different class name) under an already-claimed
  `tool_name` raises `RailsMcp::ToolNameCollision` — a genuine collision, surfaced at
  registration with both class names, not swallowed. This is not the "no-nanny" opt-out case
  (ADR-0007): it is an integrity error in the allow-list itself.

`tools` returns the registered classes in insertion order; `clear` still empties it.

## Consequences

- Development survives reloads: edit a tool, the endpoint keeps working — the single most
  common real-world dev-loop failure is removed.
- Both registration paths (central `register`, co-located `expose!`) are reload-safe with no
  per-app `clear` boilerplate.
- Genuine `tool_name` collisions are caught earlier and more clearly (at registration, naming
  both classes) than the previous downstream `ToolNotUnique`.
- Standing constraint (machine-checkable): a test registers a redefined class with the same
  `tool_name` and asserts `MCP::Server.new(tools: registry.tools)` builds without
  `ToolNotUnique` and lists the tool once; another asserts a distinct class under a taken
  `tool_name` raises `ToolNameCollision`.
- `register` remains idempotent for the same class; `registered?` is answered by `tool_name`.
