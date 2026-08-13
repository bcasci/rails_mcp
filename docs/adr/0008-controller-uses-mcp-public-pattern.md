# ADR-0008 — MCP entry point uses the `mcp` gem's public controller pattern

Status: Accepted (2026-08-13)

Supersedes: ADR-0006 (the `RailsMcp.serve` per-request mechanism). ADR-0002 (HTTP-only,
stateless), ADR-0004 (gem ships zero policy), ADR-0005 (identity rides `server_context`), and
ADR-0007 (convenience without lock-in) all stand.

## Context

Spec 0002 shipped `RailsMcp.serve`, which built a fresh `MCP::Server` per request and set the
acting user on its `server_context`. To reach the server behind the transport it used
`transport.instance_variable_get(:@server)` — a **private `mcp` internal**, the one place the
codebase depended on `mcp`'s internals and the only real upgrade risk. Separately, `mount_mcp`
/ `RailsMcp.rack_app` mounted a single boot-time server whose `server_context` had to be
mutated per request — a data race under a threaded server.

The `mcp` gem documents a **controller pattern on public API** that does exactly what `serve`
did, without the internal reach: construct `MCP::Server.new(..., server_context:)` per request
and call `StreamableHTTPTransport#handle_request(request)`, which returns `[status, headers,
body]`. This is `mcp`'s own recommended per-request-server integration — the least likely thing
to break on upgrade (ADR-0007).

## Decision

The generated `McpController` builds the server and transport **inline on public `mcp` API**:

```ruby
server = MCP::Server.new(name: "rails_mcp", tools: RailsMcp.registry.tools, server_context: {user: user})
transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
status, headers, body = transport.handle_request(request)
```

`RailsMcp.serve`, `RailsMcp::Mount` (`mount_mcp`, `RailsMcp.rack_app`, the `Router` mixin) are
**removed**. The gem's only runtime touch inside the request path is `RailsMcp.registry.tools`.
The controller keeps its fail-closed `authenticate_acting_user!` seam and remains
`McpController < ApplicationController` (app-owned). Identity still rides `server_context`
(ADR-0005); the transport stays stateless (ADR-0002).

A bare, no-per-user mount (the old `mount_mcp`) is not shipped; if an app ever needs one it is
one line of public `mcp` (`mount transport => "/mcp"`).

## Consequences

- The codebase's only dependency on a `mcp` private (`@server`) is gone; the request path is
  app-owned controller code plus public `mcp` API plus `registry.tools`.
- Per-request isolation is `mcp`'s own design (a fresh server per request), not a gem
  workaround — concurrent requests cannot bleed identity.
- The full request flow (tool selection, transport options, rendering) is visible and
  customizable in the app-owned controller (ADR-0007): tools-per-route via a custom registry
  or array, `allowed_hosts`/`allowed_origins` on the transport, custom rendering.
- Removing `mount_mcp`/`rack_app` deletes a racy convenience rather than documenting a sharp
  edge. Smaller surface, one entry point.
- Standing constraint (machine-checkable): no `instance_variable_get(:@server)` (or other
  `mcp` private reach) in `lib/`; no `mount_mcp`/`rack_app`/`RailsMcp.serve` symbols remain.
