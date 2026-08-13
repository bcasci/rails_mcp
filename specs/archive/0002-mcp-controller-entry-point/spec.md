# SPEC — `rails_mcp` authenticated MCP controller entry point

Build contract for spec 0002: an app-owned, fail-closed HTTP entry point in front of the
mounted MCP transport, so a fresh install has a place to authenticate the request and
resolve the acting staff `User` before any tool runs. Builds on the shipped v1 tool
framework (spec 0001, archived). Requirements are testable; acceptance criteria are
Given/When/Then.

All decisions are settled — `DECIDED` marks each. No `OPEN:` forks remain; the build runs
unattended. `BUILD-TIME CHECK` marks a verification a builder performs (not a decision).
Governing decision record: **ADR-0006**. Unchanged and still in force: ADR-0002 (HTTP-only,
stateless), ADR-0004 (gem ships zero policy), ADR-0005 (identity rides `server_context`).

---

## Background — the gap this closes

Spec 0001 stamped `mount_mcp '/mcp'`, mounting the stateless transport **directly** in
`config/routes.rb`. Nothing runs between the router and the protocol handler, so a fresh
install has **no app-owned place to authenticate the request** and resolve the acting staff
user. The 0001 end-to-end test hand-rolled that layer in a private harness, which hid the
gap. Separately, the `mcp` gem reads `server_context` off the server **instance**, so
per-request identity on a single boot-time server means mutating shared state — not
thread-safe under Puma. This spec adds the generated controller and a per-request serve
mechanism that close both (ADR-0006).

---

## Scope

### In this spec

- A per-request gem serve entry point that runs one MCP request with a per-request acting
  user, isolating `server_context` per request (never mutating a process-wide server).
- A generated, app-owned `McpController < ApplicationController` with a **fail-closed**
  authentication seam that raises until the implementor wires real auth.
- The generator routing `/mcp` to that controller instead of a direct `mount_mcp` mount, and
  stating — in its post-run output, the README, and the controller comments — that the
  endpoint is unauthenticated until secured.
- Integration coverage that boots the generated controller and proves fail-closed-by-default,
  per-request attribution, and no cross-request identity bleed.

### Explicitly deferred (NOT in this spec)

- **OAuth 2.1 / third-party clients** (RFC 9728/8707, PKCE, DCR) — Phase 3. v1 stays
  internal, staff-only; the controller authenticates with the app's own stack.
- **Stateful transport / sessions** — ADR-0002 stands; the transport remains stateless.
- **A specific auth mechanism** — the gem ships none. Devise, session, a bearer token, or
  anything `ApplicationController` provides is the implementor's choice.
- **Rate limiting / throttling** — app-owned, as in spec 0001.

### Gem vs app — the ownership boundary (unchanged, restated)

**The gem ships NO authentication and NO policy** (ADR-0004). It provides the per-request
serve mechanism and stamps an app-owned controller with a marked, fail-closed seam. The app
defines *what* authentication is; the gem defines *where* it goes.

**DECIDED** the entry point is a generated `McpController < ApplicationController`
(app-owned) — not a gem-shipped base controller, and not a `mount_mcp` authenticator block
(ADR-0006, options weighed).

**DECIDED** the generated controller's authentication seam **raises by default** (fail-closed),
mirroring the stamped `ApplicationMcpTool#authorize`.

**DECIDED** `mount_mcp` / `RailsMcp.rack_app` are **retained** for advanced or no-per-user
internal mounts, but are no longer the generated default; the generated path routes through
`McpController`.

---

## Requirements

### R1 — Per-request serve entry point (gem, thread-safe)

The gem exposes a public entry point the controller calls to serve **one** MCP request with a
per-request acting user. It runs the request through the same stateless transport as spec
0001, with the acting user placed on the SDK `server_context` **for that request only** — it
must not mutate a shared, process-wide `MCP::Server#server_context`. It returns a Rack
response the controller can send.

- **Given** the entry point called with a Rack request/env and `user: U`, **when** a
  registered tool is invoked, **then** `U` is the acting user reaching `authorize` and the
  `invoke.rails_mcp` payload (spec 0001 R3/R4), and the response carries the tool result.
- **Given** two requests served concurrently (interleaved) with different users `U1` and
  `U2`, **when** each invokes a tool, **then** each call sees **only** its own user — no
  cross-request identity bleed.
- **Given** the entry point, **when** it serves a request, **then** the raw request and any
  bearer token are **not** placed on `server_context` or in the payload (spec 0001 R4, R9);
  only the resolved `user:` is.
- **Given** the routed endpoint, **when** an MCP `tools/list` is made, **then** only
  registered tools are listed — identical allow-list behavior to the direct mount (spec 0001
  R6/R10).

**DECIDED** signature: `RailsMcp.serve(request, user:, registry: RailsMcp.registry,
**transport_options)` → a Rack response triple `[status, headers, body]`. `request` may be an
`ActionDispatch::Request` or a Rack env Hash (tolerant, like `user_from`). Per-request
`server_context` isolation is required; the mechanism (fresh per-request server, or an
equivalently isolated context) is the builder's choice so long as the no-bleed criterion
holds.

### R2 — Generated `McpController < ApplicationController`, fail-closed auth

The install generator stamps `app/controllers/mcp_controller.rb` as
`McpController < ApplicationController`, app-owned and editable. It carries a clearly marked
authentication seam that **raises by default** (fail-closed) until the implementor wires real
auth; on success it resolves the acting staff user and serves the request via R1. The gem
never authenticates.

- **Given** a freshly generated `McpController` with the seam left as stamped, **when** any
  request hits `/mcp`, **then** it is denied (fail-closed) and no tool runs.
- **Given** the generated file, **when** a developer reads it, **then** the authentication
  seam and the "resolve the acting staff user, then call `RailsMcp.serve`" flow are present
  as clearly marked, editable points.
- **Given** the app fills the seam to return staff user `U`, **when** a tool is invoked
  through the controller, **then** the call runs and is attributed to `U` in `authorize` and
  the audit payload.

**DECIDED** the controller inherits the app's `ApplicationController` (so it reuses the app's
existing auth: Devise, session, token, etc.). The gem does not provide the controller's
superclass.

### R3 — Route to the controller, not a direct transport mount

The generator wires `config/routes.rb` to route `/mcp` to `McpController` for the MCP request
verbs, replacing the direct `mount_mcp '/mcp'` line. The endpoint stays HTTP and stateless
(ADR-0002).

- **Given** `rails g rails_mcp:install` runs, **when** it writes routes, **then** `/mcp` is
  routed to `McpController` and the direct `mount_mcp '/mcp'` line is **not** stamped.
- **Given** the generated route, **when** the app boots, **then** `/mcp` is served through
  `McpController` and `tools/list` returns only registered tools.
- **Given** the routing, **when** the MCP client issues the request verbs the stateless
  transport uses, **then** they reach the controller action (routing does not drop a verb the
  prior direct mount served).

**DECIDED** the route dispatches all MCP request verbs to a single controller action that
delegates to `RailsMcp.serve`; the transport, not the route, decides per-verb behavior
(delegation preserved, ADR-0001).

### R4 — "You must secure this" guidance

The generator's post-run output, the README, and the generated controller comments state that
the `/mcp` endpoint is **unauthenticated until the implementor secures it**, and where to do
so.

- **Given** the generator finishes, **when** it prints its summary, **then** the output
  includes a notice that `/mcp` denies until authentication is wired in `McpController`, and
  names the file.
- **Given** the README, **when** read, **then** it documents the `McpController`
  authentication step as part of install (not only the tool `authorize` seam).
- **Given** the generated controller, **when** read, **then** the fail-closed default and the
  marked authentication seam are present with a comment pointing the implementor at their own
  auth stack.

### R5 — Identity contract unchanged (still `server_context`)

The acting user still reaches `authorize` / the audit payload via the SDK `server_context`
(ADR-0005). The controller is only the app-owned place that populates it per request. No
change to `authorize(user:, args:, tool:)` or the `invoke.rails_mcp` payload keys.

- **Given** a user `U` resolved in the controller, **when** a tool runs, **then** `U` appears
  in `authorize(user:)` and in `payload[:user]`, exactly as spec 0001 R3/R4 froze.
- **Given** a request with no valid staff identity (seam denies), **when** it is served,
  **then** it fails closed (spec 0001 R3) and no tool runs.
- **Given** the gem source, **when** audited, **then** it adds no `authorize`/payload keys and
  no authentication logic — the controller seam is app code (ADR-0004).

**BUILD-TIME CHECK** (not a decision) the builder confirms the pinned `mcp` 1.1.0 stateless
transport serves a request from a controller-supplied env and returns a Rack response usable
by R1; if the transport cannot serve from a per-request context without mutating the shared
server, the builder records it as a finding rather than shipping the race.

---

## Non-goals (restated as guardrails)

- No gem-side authentication or auth mechanism (ADR-0004); the controller seam is app-owned.
- No mutation of a shared, process-wide `server_context` for per-request identity (thread
  safety, ADR-0006).
- No OAuth / third-party client support (Phase 3); v1 stays internal, staff-only.
- No stateful/session transport (ADR-0002 stands).
- No change to the frozen `authorize` signature or `invoke.rails_mcp` payload (spec 0001
  R3/R4, ADR-0005).
