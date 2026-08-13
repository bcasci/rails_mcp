# SPEC — MCP entry point on the `mcp` gem's public controller pattern

Build contract for spec 0003: replace the `RailsMcp.serve` mechanism and the boot-time
`mount_mcp` with the `mcp` gem's documented per-request controller pattern, built inline on
public API. Removes the codebase's only dependency on an `mcp` private and shrinks the gem's
request-path surface to `RailsMcp.registry.tools`. Builds on shipped specs 0001 and 0002
(archived). Requirements are testable; acceptance criteria are Given/When/Then.

All decisions are settled — `DECIDED` marks each. No `OPEN:` forks remain; the build runs
unattended. `BUILD-TIME CHECK` marks a verification a builder performs (not a decision).
Governing decision: **ADR-0008** (supersedes ADR-0006's serve mechanism). Unchanged and in
force: ADR-0002 (HTTP-only, stateless), ADR-0004 (zero policy), ADR-0005 (identity rides
`server_context`), ADR-0007 (convenience without lock-in).

---

## Background

Spec 0002 shipped `RailsMcp.serve`, which reached the server behind the transport via
`transport.instance_variable_get(:@server)` — a private `mcp` internal, the only real
upgrade risk in the codebase. `mount_mcp` / `RailsMcp.rack_app` mounted one boot-time server
whose `server_context` had to be mutated per request (a race). The `mcp` gem documents a
public controller pattern that does the same work without either problem: build
`MCP::Server.new(..., server_context:)` per request and call
`StreamableHTTPTransport#handle_request(request)`. This spec adopts it and deletes the
superseded code (ADR-0008).

---

## Scope

### In this spec

- Rewrite the generated `McpController` to build server + transport inline on public `mcp`
  API (`MCP::Server.new(tools:, server_context:)` + `StreamableHTTPTransport#handle_request`).
- Remove `RailsMcp.serve`, `RailsMcp::Mount` (`mount_mcp`, `RailsMcp.rack_app`, the `Router`
  mixin), and everything that depended on them.
- Document the controller's customization seams (tools-per-route, transport options,
  rendering) as visible, app-owned points (ADR-0007).

### Explicitly deferred / out of scope

- The tool-creation and registration opt-out seams — spec 0004.
- Any change to `authorize`, the `invoke.rails_mcp` payload, or identity transport — frozen
  (ADR-0005; specs 0001 R3/R4).
- OAuth / stateful transport — unchanged (ADR-0002).

### Ownership boundary (restated)

The gem authenticates nothing and ships no policy (ADR-0004). The request path is app-owned
`McpController` code plus public `mcp` API plus `RailsMcp.registry.tools`.

**DECIDED** the controller builds the server/transport inline on public `mcp` API; the
`@server` private reach is removed (ADR-0008).

**DECIDED** `RailsMcp.serve`, `mount_mcp`, and `RailsMcp.rack_app` are **removed**, not
retained. A bare no-per-user mount, if ever needed, is one line of public `mcp`
(`mount transport => "/mcp"`) — not a gem feature.

**DECIDED** the controller stays `McpController < ApplicationController` with the fail-closed
`authenticate_acting_user!` seam (spec 0002 R2) unchanged.

---

## Requirements

### R1 — Controller uses the `mcp` public per-request pattern

The generated `McpController#handle` authenticates the request (fail-closed seam), then builds
an `MCP::Server` from `RailsMcp.registry.tools` with `server_context: {user: user}`, wraps it
in a stateless `StreamableHTTPTransport`, and serves the request with
`transport.handle_request(request)` — all on public `mcp` API, no `RailsMcp.serve`, no
`instance_variable_get`.

- **Given** the generated controller, **when** a registered tool is invoked through `/mcp`,
  **then** the acting user reaches `authorize` and the `invoke.rails_mcp` payload, and the
  HTTP response carries the tool result.
- **Given** the generated controller source, **when** read, **then** it references only public
  `mcp` API (`MCP::Server.new`, `StreamableHTTPTransport#handle_request`) and
  `RailsMcp.registry.tools` — no `RailsMcp.serve` and no `instance_variable_get(:@server)`.
- **Given** the mounted endpoint, **when** an MCP `tools/list` is made, **then** only
  registered tools are listed (allow-list parity, specs 0001 R6/R10).

**DECIDED** the controller constructs a **fresh** `MCP::Server` per request (the `mcp` gem's
own per-request-server integration); the acting user is set via `server_context:` at
construction, never by mutating a shared server.

### R2 — Per-request isolation preserved

Concurrent requests with different users must not bleed identity.

- **Given** two requests served concurrently (interleaved, forced to overlap in-flight) with
  users `U1` and `U2`, **when** each invokes a tool, **then** each call sees only its own user
  in `authorize` and the payload — no cross-request bleed.
- **Given** the request path, **when** audited, **then** no process-wide `MCP::Server` is
  mutated per request (each request builds its own).

### R3 — `serve` / `mount_mcp` / `rack_app` removed

The superseded mechanism is deleted, and nothing in the gem or its tests depends on it.

- **Given** `lib/`, **when** audited, **then** there is no `RailsMcp.serve`, no
  `RailsMcp::Mount`, no `mount_mcp`, no `RailsMcp.rack_app`, and no
  `instance_variable_get(:@server)` (or other `mcp` private reach).
- **Given** the gem, **when** required, **then** it loads cleanly with those files absent
  (`lib/rails_mcp.rb` no longer lists them).
- **Given** the test suite, **when** run, **then** it is green with the `serve`/`mount` unit
  tests and any boot-time-mount integration harness removed or migrated to the controller
  path.

**DECIDED** the removal includes the spec 0001 boot-time-mount integration harness
(`test/integration/dummy_app/harness.rb` and any test depending on `rack_app`), superseded by
the controller integration test (R5); shared dummy-app support still used by the controller
test is kept.

### R4 — Customization seams documented (ADR-0007)

Because the controller is app-owned and inline, an app can get specific without fighting the
gem. These are documented and reachable:

- **Given** the docs, **when** read, **then** they show how to serve a **different tool set
  per route** (a custom `RailsMcp::Registry` or a plain `tools:` array), how to pass
  **transport options** (`allowed_hosts`, `allowed_origins`, `dns_rebinding_protection`), and
  how to customize **rendering** — all in the app-owned controller.
- **Given** the generated controller, **when** read, **then** the tool source
  (`RailsMcp.registry.tools`) and the transport construction are visible, editable lines, not
  hidden behind a gem call.

### R5 — Identity, allow-list, fail-closed unchanged

No regression to the frozen contracts.

- **Given** a user `U` resolved by the controller seam, **when** a tool runs, **then** `U`
  appears in `authorize(user:)` and `payload[:user]`, exactly as specs 0001 R3/R4 froze.
- **Given** the auth seam left unwired (raises), **when** a request hits `/mcp`, **then** it
  fails closed and no tool runs (spec 0002 R2).
- **Given** the gem source, **when** audited, **then** it adds no authentication logic and no
  new `authorize`/payload keys (ADR-0004/0005).

**BUILD-TIME CHECK** (not a decision) the builder confirms mcp 1.1.0's
`StreamableHTTPTransport#handle_request(request)` accepts the `ActionDispatch`/Rack request and
returns a usable `[status, headers, body]` from a per-request server; if not, record a finding
rather than shipping.

---

## Non-goals (guardrails)

- No `mcp` private-internal reach anywhere in `lib/` (ADR-0008).
- No boot-time shared-server mount shipped by the gem (removed with `mount_mcp`).
- No change to `authorize`, the `invoke.rails_mcp` payload, identity transport, or stateless
  HTTP (ADR-0002/0005; specs 0001 R3/R4).
- No gem-side authentication (ADR-0004).
