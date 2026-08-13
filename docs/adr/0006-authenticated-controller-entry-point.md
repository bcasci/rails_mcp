# ADR-0006 — Authenticated controller entry point in front of the MCP transport

Status: Superseded by ADR-0008 (2026-08-13)

> Superseded by [ADR-0008](0008-controller-uses-mcp-public-pattern.md): the `RailsMcp.serve`
> mechanism this ADR introduced is replaced by the `mcp` gem's public controller pattern
> (inline `MCP::Server` + `StreamableHTTPTransport#handle_request`), removing the private
> `@server` reach. The app-owned, fail-closed `McpController` decision below still holds —
> only its serve mechanism changed.

## Context

Spec 0001 shipped `mount_mcp '/mcp'`, which mounts the official gem's stateless
`StreamableHTTPTransport` directly in `config/routes.rb`. That left **no app-owned place to
authenticate the HTTP request** and resolve the acting staff `User`. R9 named "the
Rack/controller layer that validates the bearer token → `User`" as app-owned, but the
install generator stamped no such layer, and no acceptance criterion graded a fresh install
as securable end to end. The 0001 end-to-end test hand-rolled that layer in a private test
harness (`test/integration/dummy_app/harness.rb`), which masked the gap: it proved the seams
work when an app wires them, while the generator gave the app nothing to wire.

A second problem sits in the same mechanism. The `mcp` gem reads `server_context` off the
**server instance** (`MCP::Server#server_context`, mcp 1.1.0 `server.rb`), not per request.
With one `MCP::Server` built at boot and mounted directly, giving each request its own acting
user means mutating that shared server's `server_context` per request — a data race under a
threaded server (Puma): two concurrent requests clobber each other's identity.

Options considered for the entry point: (a) a generated app-owned `McpController <
ApplicationController`; (b) a gem-shipped `RailsMcp::BaseController` the app subclasses and
overrides; (c) `mount_mcp` taking an authenticator block. (a) keeps the gem out of the HTTP
layer, lets the app reuse its own controller auth stack, and gives a per-request controller
instance (thread-safe) — chosen.

## Decision

The install generator stamps an **app-owned `McpController < ApplicationController`**. It
carries a fail-closed authentication seam that **raises by default** until the app implements
it (mirroring the stamped `ApplicationMcpTool#authorize`), resolves the acting staff user,
and serves the request through a **per-request gem entry point** that isolates
`server_context` for that request and never mutates a process-wide server. The generator
routes `/mcp` to this controller instead of stamping a direct `mount_mcp` mount.

The transport stays HTTP-only and stateless (ADR-0002, unchanged). Identity still rides the
SDK's `server_context` (ADR-0005, unchanged). The gem still ships no authentication and no
policy (ADR-0004): the authentication seam is app code the controller owns; the gem only
provides the per-request serve mechanism.

`mount_mcp` / `RailsMcp.rack_app` remain available for advanced or no-per-user internal
mounts, but are no longer the generated default and carry a single-shared-`server_context`
caveat in the docs.

## Consequences

- A fresh install has an obvious, fail-closed place to secure the endpoint using the app's
  own auth (Devise, session, token — whatever `ApplicationController` already provides). The
  endpoint denies every request until the implementor wires authentication.
- Per-request `server_context` is thread-safe under Puma; the boot-time-singleton race is
  removed on the generated path.
- The gem stays out of authentication and policy; the controller seam is app-owned, parallel
  to the `authorize` and audit seams.
- Constraint: the generated `McpController` must remain app-owned and fail-closed by default,
  and the gem must not perform authentication itself. The per-request serve entry must not
  rely on mutating a shared `MCP::Server#server_context`.
- Refines the R6/R8 "generator stamps a direct `mount_mcp` line" approach from spec 0001; the
  `mount_mcp` helper itself is retained, only the generated default changes.
