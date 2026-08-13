# TASKS — real-world integration hardening

Completed Thu Aug 13 11:38:54 EDT 2026 at commit 8e9c8c5

Task breakdown for spec 0005. Same constraint: **each task owns a DISJOINT set of files**.
Builds on shipped specs 0001–0004 (archived). References like `R1` point to this spec's
`spec.md`; `0001 R10` points to an archived spec.

Every task is `autonomous` — decisions are locked in spec.md / ADR-0009 / ADR-0007. The
foundation change (registry, T0) and the template/doc changes (T1, T2) are independent
(disjoint files) and build in parallel; the fixture-app integration proof (T3) depends on all
of them because it exercises the stamped output end to end.

---

## Layer 0 — Foundation + template/doc hardening (parallel)

### T0 — Reload-safe, collision-detecting registry (ADR-0009) — DONE
**Owns:**
- `lib/rails_mcp/registry.rb` (CHANGED: key by `tool_name`; reload replaces same-class-name
  entry; raise `RailsMcp::ToolNameCollision` on a different class claiming a taken `tool_name`;
  keep insertion order, idempotence, `clear`)
- `lib/rails_mcp.rb` (CHANGED only if a new error class file is added — prefer defining
  `ToolNameCollision` in `registry.rb` under the existing `RailsMcp` namespace to avoid editing
  the shared entry file)
- `test/rails_mcp/registry_test.rb` (CHANGED: reload case builds server without `ToolNotUnique`
  and lists once; genuine collision raises `ToolNameCollision`; idempotent; raw `MCP::Tool`
  keys by `tool_name`)

**Depends on:** shipped 0001/0004.
**Acceptance (R1):** all R1 criteria.
**Tag:** `autonomous` — keying + collision behavior DECIDED (ADR-0009).

### T1 — Hardened `McpController` template (Host, CSRF, before_action, shard guidance) — DONE
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED: `skip_forgery_protection`;
  build the transport with `allowed_hosts: Rails.application.config.hosts`; a marked comment to
  `skip_before_action` inherited browser auth filters; an optional marked `Current.tenant.with_shard`
  wrap around `handle_request`; corrected inheritance comment)
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED only if the post-run notice
  needs the CSRF/Host guidance)
- `test/generators/install_generator_test.rb` (CHANGED: assert the stamped controller contains
  `skip_forgery_protection`, `allowed_hosts`, the `skip_before_action` guidance comment, and the
  optional `with_shard` block)

**Depends on:** shipped 0001–0004. Independent of T0 (disjoint files).
**Acceptance (R2, R3 controller half):** R2 all; R3 controller-guidance criteria.
**Tag:** `autonomous` — hardened defaults DECIDED (R2/R3).

### T2 — `ApplicationMcpTool` tenant note + docs — DONE
**Owns:**
- `lib/generators/rails_mcp/install/templates/application_mcp_tool.rb.tt` (CHANGED: correct the
  tenant note — scoping belongs at the controller wrapping `handle_request` because `authorize`
  also needs the shard; not perform-only)
- `docs/USAGE.md` (CHANGED: tenant-scoped canonical example, or an explicit unsafe-unscoped-find
  warning; controller-level `with_shard` guidance; recovering the tenant in the subscriber)
- `docs/SEAMS.md` (CHANGED: tenant recoverable in the synchronous subscriber via `Current`; the
  payload carries no tenant by design)

**Depends on:** shipped 0001–0004. Independent of T0/T1 (disjoint files).
**Acceptance (R3 tool/doc half, R4):** R3 `ApplicationMcpTool` note; R4 all.
**Tag:** `autonomous` — guidance corrections DECIDED (R3/R4).

---

## Layer 1 — Verbatim-template fixture app (the integration proof)

### T3 — Fixture Rails app exercising the stamped templates verbatim — DONE
**Owns:**
- `test/integration/fixture_app/` (a minimal Rails app harness: a real
  `ApplicationController < ActionController::Base` with `protect_from_forgery with: :exception`;
  a router; a sharded-tenant stand-in with an observable `with_shard`; a `Current`; loads the
  **rendered** `mcp_controller.rb.tt` and `application_mcp_tool.rb.tt` as the actual controller
  and base tool)
- `test/integration/real_world_hardening_test.rb` (NEW: the R6 proofs)

**Depends on:** T0 (reload-safe registry), T1 (hardened controller), T2 (corrected tenant note).
**Acceptance (R5, R6):**
- The exercised `McpController`/`ApplicationMcpTool` are the rendered templates; a divergence
  from the stamped output fails the test (R6 verbatim).
- Cookieless JSON `POST /mcp` succeeds behind `protect_from_forgery :exception` (R2 CSRF).
- A non-loopback production `Host` in `config.hosts` is not 403'd (R2 Host).
- A tool redefined mid-run does not cause `ToolNotUnique` on the next request (R1 reload).
- With the controller wrapping `handle_request` in `with_shard`, both `authorize` and `perform`
  observe the active shard (R3).
- Auth seam unwired → fail closed, no tool runs (no regression, 0002 R2).
- The frozen contracts (authorize signature, payload keys, identity, allow-list, read-only)
  are unchanged (R5).

**Tag:** `autonomous` — R6 fixture requirements and the verbatim rule are DECIDED in spec.md.

> BUILD-TIME CHECK (R6): load the real `.tt` output (ERB-rendered), not a hand-copied
> controller. If a template cannot render in-suite without a full Rails app, record how the
> fixture still guarantees verbatim fidelity (e.g. asserting the exercised source equals the
> rendered template).

---

## Dependency graph (build order)

```
(shipped 0001-0004)
T0 ┐
T1 ┼─→ T3
T2 ┘
```

T0/T1/T2 are independent (disjoint files), parallel after the shipped base. T3 (fixture proof)
waits on all three — it exercises their combined stamped output.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0009 / ADR-0007 — do not relitigate):**

- Registry keys by `tool_name`; reload replaces same-class-name; different class on a taken
  name raises `ToolNameCollision`; idempotent; insertion order; `clear` kept.
- Stamped controller: `skip_forgery_protection`; `allowed_hosts: Rails.application.config.hosts`;
  `skip_before_action` guidance; optional `with_shard` wrap; corrected inheritance comment.
- Tenant/shard guidance at the controller (wraps `handle_request`), not perform-only.
- Canonical example is tenant-safe; tenant recoverable in the synchronous subscriber.
- The fixture app runs the rendered templates verbatim; a diverging test is itself a failure.
- No change to authorize, payload, identity, stateless HTTP, or read-only scope.

No open decisions remain — every task is `autonomous`; the build runs unattended.
