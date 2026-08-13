# TASKS — `rails_mcp` authenticated MCP controller entry point

Completed Thu Aug 13 09:02:36 EDT 2026 at commit 7d3ff1c

Task breakdown for spec 0002. Same hard constraint as 0001: **each task owns a DISJOINT set
of files** — no two tasks in this spec touch the same file, so agents build without merge
conflicts. This spec builds on the shipped v1 framework (spec 0001, archived): `RailsMcp::Tool`
(0001 T4), `mount_mcp` + `RailsMcp::Registry` + `RailsMcp.rack_app` (0001 T5), and the install
generator + templates (0001 T6). Editing those shipped generator files is fine — the
disjoint-file rule is about parallel tasks **within this spec**.

Every task is `autonomous` — all decisions are locked as `DECIDED` in spec.md and ADR-0006, so
the build runs unattended. References like `R1` point to this spec's `spec.md`; `0001 R3`
points to the archived spec.

The top-level constant is `RailsMcp`; the tool dir is `app/mcp/`; controllers live in
`app/controllers/`.

---

## Layer 0 — Per-request serve runtime (must land first)

### T0 — `RailsMcp.serve` per-request entry point — DONE
**Owns:**
- `lib/rails_mcp/serve.rb` (the `RailsMcp.serve(request, user:, registry:, **opts)` entry
  point; per-request `server_context` isolation over the stateless transport; returns a Rack
  response triple)
- `test/rails_mcp/serve_test.rb`
- `lib/rails_mcp.rb` — **this task is the sole editor of the shared require file** in this
  spec: it adds the `require_relative "rails_mcp/serve"` line. No other 0002 task edits it.

**Depends on:** shipped 0001 T4 (`RailsMcp::Tool`), 0001 T5 (`RailsMcp.rack_app`, registry).
**Acceptance (R1, R5):**
- `RailsMcp.serve(env, user: U, registry: r)` serves one request; a registered tool invoked
  through it sees `U` in `authorize` and `payload[:user]`; the Rack response carries the tool
  result.
- Two interleaved `serve` calls with different users `U1`/`U2` each see only their own user —
  no cross-request identity bleed (the thread-safety criterion; assert with real concurrent
  or interleaved invocations, not a mock).
- `tools/list` through `serve` returns only registered tools (allow-list parity with the
  direct mount, 0001 R6/R10).
- The raw request/env and any bearer token never reach `server_context` or the payload — only
  the resolved `user:` (0001 R4/R9).
- Accepts an `ActionDispatch::Request` or a Rack env Hash (tolerant input).

**Tag:** `autonomous` — R1 signature and per-request-isolation requirement DECIDED; identity
transport is `server_context` (ADR-0005).

> `RailsMcp.serve` must not mutate a shared `MCP::Server#server_context` across concurrent
> requests (ADR-0006). Fresh per-request server or an equivalently isolated context — the
> builder chooses, so long as the no-bleed test passes. BUILD-TIME CHECK: confirm mcp 1.1.0's
> stateless transport can serve from a controller-supplied env and return a Rack response; if
> not, record a finding rather than shipping the race (R5).

---

## Layer 1 — Generator: controller, route, security notice

### T1 — Generated `McpController` + route change + generator output — DONE
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (NEW:
  `McpController < ApplicationController`; fail-closed authentication seam that raises by
  default; on success resolves the acting staff user and calls `RailsMcp.serve`; clearly
  marked, commented seams; the "secure this endpoint" notice)
- `lib/generators/rails_mcp/install/templates/routes_mount.rb.tt` (CHANGED: route `/mcp` to
  `McpController` for the MCP request verbs, replacing the direct `mount_mcp '/mcp'` line)
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED: add
  `create_mcp_controller`; update route injection to the controller route; add a post-run
  message stating `/mcp` is unauthenticated until secured in `McpController`, naming the file)
- `test/generators/install_generator_test.rb` (CHANGED: assert the controller is stamped,
  fail-closed by default, with the marked seam; assert the route targets `McpController` and
  the direct `mount_mcp '/mcp'` line is NOT stamped; assert the generator output carries the
  security notice)

**Depends on:** T0 (the controller calls `RailsMcp.serve`).
**Acceptance (R2, R3, R4):**
- Generator creates `app/controllers/mcp_controller.rb` as
  `McpController < ApplicationController`, fail-closed (denies until auth is wired), with the
  authentication seam and the resolve-user → `RailsMcp.serve` flow as marked editable points.
- The route targets `McpController` for the MCP verbs; the direct `mount_mcp '/mcp'` line is
  not stamped; a booted route serves `/mcp` through the controller and `tools/list` returns
  only registered tools.
- The generator's post-run output includes the "unauthenticated until you secure
  `McpController`" notice naming the file.

**Tag:** `autonomous` — controller shape, fail-closed default, and route change all DECIDED
(R2/R3, ADR-0006).

---

## Layer 2 — Docs + end-to-end verification through the controller

### T2 — README + docs + controller integration test — DONE
**Owns:**
- `README.md` (CHANGED: document the `McpController` authentication step as part of install —
  the endpoint denies until secured — alongside the existing tool `authorize` seam)
- `docs/USAGE.md` (CHANGED: add the HTTP entry point / `McpController` auth section and the
  `RailsMcp.serve` flow; note `mount_mcp`'s retained-but-not-default status and its
  single-shared-`server_context` caveat)
- `docs/SEAMS.md` (CHANGED: note that the acting user is populated per request in
  `McpController` and rides `server_context` unchanged, ADR-0005/0006)
- `test/integration/controller_end_to_end_test.rb` (NEW: boot a dummy app that routes `/mcp`
  through a controller equivalent to the generated template; prove fail-closed BEFORE auth is
  wired, per-request attribution to the real staff user AFTER, and no cross-request identity
  bleed — exercising generator-shaped code, not a bespoke hand-rolled harness)

**Depends on:** T0 (`RailsMcp.serve`), T1 (controller/route shape the test and docs mirror).
**Acceptance (R2, R4, R5 integrated):**
- Through the routed `McpController`, a request with the auth seam unwired fails closed and no
  tool runs; with the seam returning staff user `U`, the tool runs attributed to `U` in the
  audit payload.
- Two interleaved requests carrying different users do not bleed identity (end-to-end mirror
  of the T0 unit criterion).
- Docs reflect, exactly as built: the `McpController` fail-closed default, the resolve-user →
  `RailsMcp.serve` flow, and the unchanged `authorize`/payload contract.

**Tag:** `autonomous` — the contracts (R1/R2/R5) are frozen in spec.md; docs and the
integration test reflect them.

---

## Dependency graph (build order)

```
(shipped 0001: T4 Tool, T5 mount/registry/rack_app, T6 generator+templates)
T0 ─→ T1 ─→ T2
```

Linear: T0 provides `RailsMcp.serve`; T1's controller calls it; T2's docs + integration test
mirror T1's controller and T0's runtime.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0006 — do not relitigate):**

- Entry point: generated `McpController < ApplicationController` (app-owned) — not a
  gem-shipped base controller, not a `mount_mcp` authenticator block.
- The controller's authentication seam raises by default (fail-closed), mirroring
  `ApplicationMcpTool#authorize`.
- Per-request `server_context` isolation; no mutation of a shared, process-wide server.
- `RailsMcp.serve(request, user:, registry:, **opts)` → Rack response triple.
- Route `/mcp` to the controller; the direct `mount_mcp '/mcp'` line is no longer stamped.
- `mount_mcp` / `RailsMcp.rack_app` retained for advanced/no-per-user mounts, not the default.
- Identity still rides `server_context` (ADR-0005); no change to `authorize` signature or the
  `invoke.rails_mcp` payload (0001 R3/R4).

No open decisions remain — every task is `autonomous`; the build runs unattended.
