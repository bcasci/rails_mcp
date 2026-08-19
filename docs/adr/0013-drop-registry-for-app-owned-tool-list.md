# ADR-0013 — Drop `RailsMcp::Registry` for an app-owned tool list

Status: Accepted (2026-08-19)

Supersedes: ADR-0009 (registry keyed by tool name) and the spec-0004 `expose!` decision;
supersedes the registry framing of spec 0001 R10. ADR-0012 (neutral conduit) governs; ADR-0008
(public controller pattern), ADR-0005 (identity on `server_context`), and ADR-0004 (zero policy)
stand.

## Context

`RailsMcp::Registry` is a process-wide, boot-time mutable accumulator: tools are pushed in via
`register` (in `to_prepare`) or `expose!`, and the generated `McpController` reads
`RailsMcp.registry.tools`. The supposed value is the allow-list — but the allow-list is the
`mcp` gem's, not ours: `MCP::Server` stores only the tools passed to `tools:`
(`@tools = tools.to_h { |t| [t.name_value, t] }`, server.rb:174) and refuses any `tools/call`
for a name not in that set (`tool = tools[tool_name]; unless tool … raise "Tool not found"`,
server.rb:754-758). The array handed to `MCP::Server.new(tools:)` *is* the allow-list, enforced
by `mcp` regardless of where the array came from.

The registry adds a gem concept, a mutable singleton, `expose!`, `ToolNameCollision`, and the
ADR-0009 reload/collision machinery — and that machinery exists only to fix a hazard the
boot-time-accumulator design created (stale classes piling up across Zeitwerk reloads, crashing
on duplicate `tool_name`). A plain app-owned list that names its tool constants and is resolved
**per request** has no such hazard: each request references the current, reloaded classes.
Multiple servers / per-route tool sets — which `mcp`'s per-request controller pattern supports
natively — are also cleaner with explicit lists than a single global registry. Per ADR-0012 the
gem adds conventions only for genuine benefit and must not obscure `mcp`; a named list is a
benefit an app gets for free from ordinary Ruby.

## Decision

Remove `RailsMcp::Registry` (`RailsMcp.registry`, `register`, `registered?`, `tools`, `clear`,
`ToolNameCollision`) and the `expose!` macro. The generator stamps an **app-owned** tool list —
`app/mcp/registered_tools.rb`, a module whose `.all` returns an explicit array of tool classes —
and the generated `McpController#handle` passes `tools: RegisteredTools.all` (resolved per
request) to `MCP::Server.new`. The initializer no longer registers tools (its audit-subscribe
half stays).

The allow-list guarantee is unchanged — it is `mcp`'s. A duplicate `tool_name` is still caught,
by `mcp`'s `ToolNotUnique` at `MCP::Server.new`. Auto-discovery remains rejected (ADR-0007): the
list is an explicit, deliberate act.

This is a breaking change to public seams; the gem has no consumers yet, so no deprecation cycle
— the version bumps 0.1.0 → 0.2.0 (semver 0.x breaking = minor).

## Consequences

- Less gem surface, closer to `mcp` (the app hands `MCP::Server` an array, as `mcp` intends).
- Reload-safe by construction — the per-request list references current classes; no ADR-0009
  keying/collision code, no `to_prepare` accumulation.
- Per-route / multiple-server tool sets are just multiple lists, no global-registry contortion.
- Lost: `expose!` co-location and the earlier `ToolNameCollision` message (now `mcp`'s
  `ToolNotUnique`, at server build). Both minor.
- Standing constraint (machine-checkable): `grep` of `lib/` finds no `RailsMcp::Registry`,
  `RailsMcp.registry`, `register`, `expose!`, or `ToolNameCollision`; the generated controller
  passes an app-owned `tools:` array, not a gem registry.
