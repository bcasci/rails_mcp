# TASKS — MCP entry point on the `mcp` gem's public controller pattern

Task breakdown for spec 0003. Same constraint: **each task owns a DISJOINT set of files**.
Builds on shipped specs 0001/0002 (archived): `RailsMcp::Tool`, `RailsMcp::Registry`, the
install generator + `McpController` template, and the controller integration test.

Every task is `autonomous` — decisions are locked in spec.md / ADR-0008. `R1` points to this
spec's `spec.md`; `0002 R2` points to the archived spec. The chain is linear: T0 moves all
code onto the public pattern, T1 deletes the now-dead mechanism, T2 documents.

---

## Layer 0 — Adopt the public controller pattern

### T0 — Rewrite `McpController` template + controller integration test to public `mcp` API
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED: `#handle` builds
  `MCP::Server.new(name:, tools: RailsMcp.registry.tools, server_context: {user: user})` +
  `StreamableHTTPTransport.new(server, stateless: true)` + `transport.handle_request(request)`;
  keep the fail-closed `authenticate_acting_user!` seam; no `RailsMcp.serve`, no ivar reach)
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED: drop any `RailsMcp.serve`
  / `mount_mcp` references in comments or the post-run notice; the route template already
  targets `mcp#handle` — leave it)
- `test/generators/install_generator_test.rb` (CHANGED: assert the controller uses the public
  pattern — `MCP::Server.new`, `handle_request` — and contains no `RailsMcp.serve` and no
  `instance_variable_get`)
- `test/integration/controller_end_to_end_test.rb` (CHANGED: rewrite its mirrored controller
  to the public pattern; keep the fail-closed-before-auth, per-request attribution, and
  no-identity-bleed assertions — R1, R2, R5)

**Depends on:** shipped 0001/0002. (After this task, nothing references `RailsMcp.serve`,
`mount_mcp`, or `rack_app`.)
**Acceptance (R1, R2, R5):**
- The stamped controller invokes a registered tool end to end; the acting user reaches
  `authorize` + the payload; `tools/list` returns only registered tools.
- The controller references only public `mcp` API + `RailsMcp.registry.tools`; no
  `RailsMcp.serve`, no `instance_variable_get(:@server)`.
- Two interleaved requests with different users do not bleed identity.
- Auth seam unwired → fail closed, no tool runs.

**Tag:** `autonomous` — public pattern + fresh-per-request server DECIDED (R1, ADR-0008).

---

## Layer 1 — Remove the superseded mechanism

### T1 — Delete `serve` / `mount` + dependents
**Owns:**
- `lib/rails_mcp/serve.rb` (DELETE)
- `lib/rails_mcp/mount.rb` (DELETE — `mount_mcp`, `RailsMcp.rack_app`, `Router` mixin)
- `test/rails_mcp/serve_test.rb` (DELETE)
- `test/rails_mcp/mount_test.rb` (DELETE)
- `test/integration/dummy_app/harness.rb` (DELETE — the boot-time-mount harness using
  `rack_app`) and any spec 0001 integration test that depends on it (e.g.
  `test/integration/end_to_end_test.rb`); keep shared dummy-app support files still required by
  `controller_end_to_end_test.rb`
- `lib/rails_mcp.rb` (CHANGED: remove the `rails_mcp/mount` and `rails_mcp/serve` lines from
  the submodule load list)

**Depends on:** T0 (nothing references the removed symbols after T0).
**Acceptance (R3):**
- `lib/` contains no `RailsMcp.serve`, `RailsMcp::Mount`, `mount_mcp`, `RailsMcp.rack_app`, or
  `instance_variable_get(:@server)`.
- `require "rails_mcp"` loads cleanly with the files absent.
- Full suite green with the deleted unit tests and the retired boot-time-mount harness gone.

**Tag:** `autonomous` — removal set DECIDED (R3, ADR-0008).

---

## Layer 2 — Document the customization seams

### T2 — README + docs for the inline controller and its seams
**Owns:**
- `README.md` (CHANGED: the install section shows the inline controller; drop any `mount_mcp`
  mention)
- `docs/USAGE.md` (CHANGED: replace the `RailsMcp.serve` / `mount_mcp` sections with the
  public controller pattern; document tools-per-route via a custom registry or a plain
  `tools:` array, transport options, and custom rendering — R4)
- `docs/SEAMS.md` (CHANGED: note the entry point is the app-owned controller on public `mcp`
  API; identity still rides `server_context`, unchanged)

**Depends on:** T0 (controller shape), T1 (removed symbols so docs don't reference them).
**Acceptance (R4):**
- Docs show, exactly as built: the inline `MCP::Server` + `handle_request` controller, the
  per-route tool-set seam, transport options, and rendering — all app-owned.
- No doc references `RailsMcp.serve`, `mount_mcp`, or `RailsMcp.rack_app`.

**Tag:** `autonomous` — the pattern and seams are frozen in spec.md; docs reflect them.

---

## Dependency graph (build order)

```
(shipped 0001/0002)
T0 ─→ T1 ─→ T2
```

Linear: T0 moves all code to the public pattern; T1 deletes the dead mechanism; T2 documents.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0008 — do not relitigate):**

- Controller builds server + transport inline on public `mcp` API; no `@server` reach.
- Fresh `MCP::Server` per request; user via `server_context:` at construction.
- `RailsMcp.serve`, `mount_mcp`, `RailsMcp.rack_app` removed; no bare mount shipped.
- `McpController < ApplicationController` + fail-closed `authenticate_acting_user!` unchanged.
- Identity on `server_context`, allow-list, `authorize`/payload all unchanged (ADR-0005; 0001
  R3/R4).

No open decisions remain — every task is `autonomous`; the build runs unattended.
