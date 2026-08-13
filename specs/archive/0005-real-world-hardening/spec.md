# SPEC — real-world integration hardening

Build contract for spec 0005: fix the foundational gaps that a real Rails integration hits on
first use — dev reload, production Host, the `ApplicationController` inheritance costs, and
sharded-multitenant scope placement — and prove them with a **fixture Rails app that exercises
the stamped templates verbatim**, so no test can pass by diverging from the generated code.
Builds on shipped specs 0001–0004 (archived). Requirements are testable; acceptance criteria
are Given/When/Then.

All decisions are settled — `DECIDED` marks each. No `OPEN:` forks remain. Governing decisions:
**ADR-0009** (registry keyed by tool name) and **ADR-0007** (convenience without lock-in).
Unchanged and in force: ADR-0002 (stateless HTTP), ADR-0004 (zero policy), ADR-0005
(identity on `server_context`), ADR-0008 (public controller pattern).

---

## Background — why these escaped

The gem's tests were green but mis-scoped: the controller integration test passed
`allowed_hosts: ["example.org"]` that the **stamped template omits**; it ran a
`McpController < ActionController::Base`, not a real `ApplicationController`; the reload test
re-ran `expose!` on the *same* class, not a redefined one; the tenant was a stub with no real
`with_shard`. Every gap lived in the gem↔app seam the tests never reached. This spec closes
the gaps **and** the testing blind spot (a verbatim-template fixture app, R6).

---

## Scope

### In this spec

- Reload-safe, collision-detecting registry (ADR-0009).
- Hardened `McpController` template: production `allowed_hosts`, `skip_forgery_protection`,
  guidance to skip inherited browser auth filters, corrected inheritance comment.
- Tenant/shard guidance moved to the controller (wrap `handle_request`); corrected
  `ApplicationMcpTool` tenant comment.
- Tenant-scoped canonical example; document recovering the tenant in the subscriber.
- A fixture Rails app in the test suite that runs the **stamped templates verbatim** under a
  real `ApplicationController` (with `protect_from_forgery`), a reload cycle, a production Host,
  and a sharded-tenant stand-in.

### Out of scope

- OAuth / third-party clients (Phase 3); the entry point, identity, payload, and stateless
  transport are unchanged (ADR-0002/0005/0008).
- The factory-process corrections (a spec-completeness critic; banning diverging test
  harnesses) — those are changes to `.claude/` tooling, tracked separately from this gem spec.

**DECIDED** the registry keys by `tool_name`, reload-safe, raising `ToolNameCollision` on a
genuine collision (ADR-0009).

**DECIDED** the stamped controller defaults `allowed_hosts:` from `Rails.application.config.hosts`
and calls `skip_forgery_protection`; both are visible, app-editable lines.

**DECIDED** tenant/shard scoping is guided at the **controller** (wrapping `handle_request`),
because the invoke pipeline runs `authorize` before `perform` and both need the shard; the
`ApplicationMcpTool` perform-level tenant note is corrected to point there.

**DECIDED** the integration test renders and loads the **actual generator templates** (not a
hand-mirrored copy); a test fails if the exercised controller diverges from the stamped one.

---

## Requirements

### R1 — Reload-safe, collision-detecting registry (ADR-0009)

- **Given** a tool class `Foo::BarTool` (`tool_name "foo_bar"`) registered, then **redefined**
  (a new class object, same class name and `tool_name`) and registered again, **when**
  `MCP::Server.new(tools: RailsMcp.registry.tools)` is built, **then** it does **not** raise
  `ToolNotUnique` and the tool is listed exactly once (the reload case).
- **Given** two **different** classes (`A`, `B`, different class names) both declaring
  `tool_name "dup"`, **when** the second is registered, **then** `RailsMcp::ToolNameCollision`
  is raised, naming both classes.
- **Given** the same class registered twice, **when** the registry is read, **then** it appears
  once (idempotent), preserving insertion order for distinct tools.
- **Given** a raw `MCP::Tool` (spec 0004 R4), **when** registered, **then** it keys by its
  `tool_name` the same way (no regression to the unaudited path).

### R2 — Hardened controller template (production Host + CSRF)

- **Given** the stamped `McpController`, **when** served under a non-loopback production `Host`
  (e.g. `boswell.fly.dev`) that is in `Rails.application.config.hosts`, **then** the request is
  **not** rejected by the SDK DNS-rebinding guard (no `403 Forbidden: Invalid Host header`) —
  the template passes `allowed_hosts:` from the app's host allow-list by default.
- **Given** the stamped `McpController` behind an `ApplicationController` with
  `protect_from_forgery with: :exception`, **when** an MCP client sends a cookieless JSON `POST`
  with no CSRF token, **then** the request is **not** rejected with
  `InvalidAuthenticityToken` — the template calls `skip_forgery_protection`.
- **Given** the stamped controller, **when** read, **then** it carries a marked comment to
  `skip_before_action` any inherited browser auth filter (e.g. Devise `authenticate_user!`)
  that would 302-redirect a machine client, and the inheritance comment no longer implies the
  app's `before_action` stack works unchanged for a token endpoint.

### R3 — Tenant/shard guidance at the controller

- **Given** the stamped controller, **when** read, **then** it documents (as an optional,
  clearly-marked block) wrapping `handle_request` in the app's tenant scope
  (`Current.tenant.with_shard { ... }`) so **both** `authorize` and `perform` run in-shard.
- **Given** the stamped `ApplicationMcpTool`, **when** read, **then** its tenant note no longer
  advises scoping only inside `perform`; it points to the controller as the correct layer and
  explains that `authorize` also needs the shard.
- **Given** a sharded fixture where the controller wraps `handle_request` in `with_shard`,
  **when** a tool runs, **then** the shard is active during **both** `authorize` and `perform`
  (proven in R6).

### R4 — Safe canonical example + tenant-in-audit docs

- **Given** `docs/USAGE.md`, **when** read, **then** the canonical example queries through the
  tenant / a scoped relation (not an unscoped global `Model.find`), or explicitly flags an
  unscoped find as unsafe for multitenant apps.
- **Given** `docs/SEAMS.md`/`docs/USAGE.md`, **when** read, **then** they document that the
  tenant is recoverable in the `invoke.rails_mcp` subscriber via `Current` (the subscriber runs
  synchronously on the request thread), since the frozen payload carries no tenant.

### R5 — No regressions to the frozen contracts

- **Given** the changes, **when** the suite runs, **then** `authorize(user:, args:, tool:)`,
  the `invoke.rails_mcp` payload keys, identity on `server_context`, the allow-list, and the
  read-only v1 scope are all unchanged (specs 0001/0003; ADR-0005/0008).

### R6 — Fixture Rails app runs the stamped templates verbatim

A representative Rails app in the test suite exercises the **generated output**, not a copy.

- **Given** the install generator's templates, **when** the fixture boots, **then** its
  `McpController` and `ApplicationMcpTool` are the **rendered templates** (loaded from
  `lib/generators/.../templates/*.tt`), and a test fails if the exercised controller diverges
  from the stamped one.
- **Given** the fixture's `ApplicationController` with `protect_from_forgery with: :exception`,
  **when** a cookieless JSON `POST /mcp` arrives, **then** it succeeds (proving R2 CSRF).
- **Given** the fixture served under a non-loopback production `Host` in `config.hosts`, **when**
  a request arrives, **then** it is not 403'd (proving R2 Host).
- **Given** the fixture with a tool redefined mid-run (reload stand-in), **when** the next
  request builds the server, **then** no `ToolNotUnique` (proving R1 reload).
- **Given** the fixture with a sharded-tenant stand-in and the controller wrapping
  `handle_request` in `with_shard`, **when** a tool runs, **then** both `authorize` and
  `perform` observe the active shard (proving R3).
- **Given** the fail-closed auth seam unwired, **when** a request arrives, **then** it fails
  closed and no tool runs (no regression to spec 0002 R2).

**BUILD-TIME CHECK** (not a decision) the builder confirms the fixture loads the real `.tt`
output (ERB-rendered) rather than duplicating it; if a template cannot be rendered in-suite
without a full Rails app, the builder records how the fixture guarantees verbatim fidelity.

---

## Non-goals (guardrails)

- No change to `authorize`, the payload, identity transport, stateless HTTP, or read-only
  scope (specs 0001–0004; ADRs 0002/0005/0008).
- No gem-side authentication, policy, tenant, or audit persistence (ADR-0004) — the controller
  and tenant scoping remain app-owned; the gem only hardens the stamped defaults and guidance.
- No test that passes by diverging from the stamped templates (R6).
