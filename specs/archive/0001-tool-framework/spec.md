# SPEC — `rails_mcp`

Build contract for the `rails_mcp` gem: a thin conventions-and-seams layer over the
official `mcp` gem (`modelcontextprotocol/ruby-sdk`) that exposes selected Rails app
actions to an AI client over MCP. Derived from the idea docs in
`ideas/07-rails-mcp-action-server/`. Requirements are testable; acceptance criteria are
Given/When/Then.

All decisions are settled — `DECIDED` marks each. No `OPEN:` forks remain; the build runs
unattended. `BUILD-TIME CHECK` marks a verification a builder performs (not a decision).

---

## Scope

### v1 — READ-ONLY

v1 ships the gem, its install generator, and the ability to register and invoke
**read-only diagnostic tools only**. No tool may mutate. The value proposition of v1 is
that it is safer than SSH + `rails runner` the day it ships: allow-list + attribution +
audit, with near-zero blast radius (no mutations).

**In v1:**

- The tool base class (`RailsMcp::Tool`) with an args DSL and a `perform` convention.
- The `authorize` seam (called before `perform`, fail-closed).
- One `ActiveSupport::Notifications` event per tool call (the audit seam).
- Tool annotations passed through the DSL (`readOnlyHint`, etc.).
- The `mount_mcp` route helper over the official gem's Rack transport.
- The `rails g rails_mcp:install` generator (Devise-style) that stamps an app-owned,
  fail-closed `ApplicationMcpTool`, a `/mcp` mount, an initializer, one read-only example
  tool, and example tests.
- The allow-list guarantee: the AI can invoke only registered tools, with only their
  declared args.

### Explicitly deferred (NOT in v1)

- **Mutating tools** (`destructiveHint: true`) — Phase 2.
- **Human-in-the-loop approval tiers** (in-chat elicitation or out-of-band approve-in-UI)
  — Phase 2. The gem may leave the seam usable, but no approval flow ships in v1.
- **Full OAuth 2.1** (RFC 9728 Protected Resource Metadata, RFC 8707 audience binding,
  PKCE, DCR, external Authorization Server) — Phase 3, only if `/mcp` opens to third-party
  clients. v1 uses an internal staff-only bearer token.
- **Rate limiting** as a gem feature — app-owned; the per-call seam is the throttle point.
- **A second/third app rollout** — Phase 2. v1 proves the seams against app #1 only.

### Gem vs app — the ownership boundary

**The gem ships NO policy.** Specifically the gem ships:

- No audit table or audit sink.
- No permission / authorization model (no Pundit calls, no policy classes).
- No tenant / shard logic.
- No staff-user resolution.
- No approval flow.

Those are **app-owned seams**, wired in the generated `app/mcp/application_mcp_tool.rb`
using the app's own stack (Pundit, its audit trail, its sharding). The gem defines *where*
authz, audit, and tenant scoping happen; the app defines *what* they are.

**DECIDED** gem name `rails_mcp`, top-level constant `RailsMcp`.

**DECIDED** version floor: `required_ruby_version >= 3.2`, Rails dependency `>= 7.1`
(broadened below the target apps so older apps can adopt the gem).

**DECIDED** v1 ships **HTTP only** (Streamable HTTP, stateless — see R6). stdio is not
shipped in v1 (does not fit remote production support).

---

## Requirements

### R1 — Tool base class + args DSL

`RailsMcp::Tool` is the base class app tools subclass (directly or via
`ApplicationMcpTool`). It provides a class-level args DSL for declaring typed, named
arguments, and each declared arg becomes part of the tool's MCP input schema. Only declared
args are accepted; the AI cannot pass arbitrary arguments.

- **Given** a tool declaring `arg :household_id, :integer, required: true`, **when** the
  server advertises the tool, **then** the tool's MCP input schema lists `household_id` as
  a required integer.
- **Given** a tool with a required arg, **when** it is invoked without that arg, **then**
  the call is rejected with a schema/validation error and `perform` is not run.
- **Given** an invocation carrying an argument the tool did not declare, **when** the tool
  runs, **then** the undeclared argument is not passed into `perform` (allow-list on args).
- **Given** an arg typed `:integer`, **when** invoked with a non-integer value, **then**
  the call is rejected before `perform`.

**DECIDED** args validation delegates to the official `mcp` gem's JSON-Schema `input_schema`
(no hand-rolled type engine). The DSL builds the `input_schema`; the gem validates against it.

### R2 — `perform` convention

A tool defines its behavior in an instance method `perform(**declared_args)`, which
receives the declared args as keyword arguments and returns a response the transport can
serialize. A helper (e.g. `text_response(str)`) produces a text tool result.

- **Given** a tool with `def perform(household_id:)`, **when** invoked with
  `household_id: 42`, **then** `perform` runs with `household_id == 42` and its return
  value is returned to the client as the tool result.
- **Given** `perform` returns `text_response("ok")`, **when** invoked, **then** the client
  receives a text content result equal to `"ok"`.
- **Given** `perform` raises, **when** invoked, **then** the error is surfaced as a tool
  error (not a leaked stack that exposes secrets) and the per-call notification records the
  error (see R4).

### R3 — `authorize` hook (fail-closed seam)

`RailsMcp::Tool` calls an `authorize` seam **before** `perform` on every invocation,
passing the call context (at minimum the acting staff user and the args). The gem ships no
policy: its default `authorize` must **fail closed** — raise/deny unless the app has
provided an implementation. Authorization runs before any work in `perform`.

- **Given** a tool whose `authorize` is not overridden, **when** invoked, **then** the call
  is denied and `perform` never runs (fail-closed default).
- **Given** an app `ApplicationMcpTool` that overrides `authorize` to raise on a failed
  Pundit check, **when** an unauthorized staff user invokes the tool, **then** `perform`
  never runs and the call returns an authorization error.
- **Given** `authorize` passes, **when** invoked, **then** `perform` runs.

**DECIDED** `authorize` signature is `authorize(user:, args:, tool:)` — keyword args, the
guaranteed context contract app code depends on: `user:` (the acting staff user), `args:`
(the declared args hash), `tool:` (the tool instance/class). App overrides accept `**` to
stay forward-compatible.

### R4 — Per-call `ActiveSupport::Notifications` event (audit seam)

The gem emits exactly one `ActiveSupport::Notifications` event per tool invocation. The
event payload carries: acting staff user, tool class/name, the args, and the
result-or-error. The gem does **not** persist anything — it only publishes the event. The
app is responsible for subscribing and writing an audit row.

- **Given** any tool invocation (success or failure), **when** it completes, **then**
  exactly one notification is instrumented with the agreed event name.
- **Given** a successful invocation, **when** the event fires, **then** its payload
  includes the staff user, tool name, args, and result marker.
- **Given** a `perform` that raises, **when** the event fires, **then** its payload records
  the error (invocation still emits exactly one event).
- **Given** the gem alone (no app subscriber), **when** a tool runs, **then** no audit
  record is written by the gem (audit is app-owned).

**DECIDED** event name is `"invoke.rails_mcp"`. Payload keys (the public contract apps
subscribe to): `user:` (acting staff user), `tool:` (tool name/class), `args:` (declared
args), and `result:` or `error:` (exactly one). No other keys.

**DECIDED (enforced)** the payload and every gem log line exclude bearer tokens and
credentials — a CI grep guards it. Not a fork; a standing rule (ADR-0004).

### R5 — Tool annotations passed through the DSL

The DSL lets a tool declare its MCP annotation tier (at least `read_only!` →
`readOnlyHint: true`), and these annotations are emitted to the client via the official
gem. In v1 all shipped/example tools are read-only. The gem must treat annotations as
advisory and not rely on the client honoring them.

- **Given** a tool that calls `read_only!`, **when** the server advertises it, **then** the
  advertised tool carries `readOnlyHint: true`.
- **Given** a tool that does not declare an annotation, **when** advertised, **then** it is
  treated as maximally dangerous (not silently marked read-only).

**DECIDED** no server-side tier enforcement in v1 — v1 is read-only, so there are no
mutating tools to gate. Deferred to Phase 2 when mutations arrive.

**BUILD-TIME CHECK** (not a decision) the T2 builder verifies the pinned `mcp` gem version
actually emits annotations (SDK issue #259) and pins a version that does; if none does, it
records the gap as a finding rather than blocking.

### R6 — `mount_mcp` route helper

The gem provides a one-line route helper, `mount_mcp` (usable as `mount_mcp '/mcp'` or
equivalent in `config/routes.rb`), that mounts the official gem's Rack transport so a
registered set of tools is served at the given path in the same Rails process.

- **Given** `mount_mcp '/mcp'` in routes, **when** the app boots, **then** an MCP endpoint
  is reachable at `/mcp` in the same process/deploy as the web app.
- **Given** the mounted endpoint, **when** an MCP `tools/list` request is made, **then**
  only registered tools are listed.
- **Given** the mounted endpoint, **when** an MCP `tools/call` names an unregistered tool,
  **then** the call is refused (allow-list, see R10).

**DECIDED** `mount_mcp` configures the official SDK's **stateless** mode (avoids SSE
idle-timeout/thread-starvation on Fly). AI clients maintain their own session state.

### R7 — Generated app-owned `ApplicationMcpTool`

The install generator stamps `app/mcp/application_mcp_tool.rb` as
`ApplicationMcpTool < RailsMcp::Tool`, app-owned and editable, that is **fail-closed** and
carries clearly commented seams for `authorize` and audit. This mirrors
`ActionController::Base` → `ApplicationController`. The gem presumes no tenancy; any scoping
is ordinary app code the implementor adds here if their app needs it.

- **Given** a freshly generated `ApplicationMcpTool` with seams left as stamped, **when** a
  tool subclassing it is invoked, **then** it fails closed (denies) rather than running
  unguarded.
- **Given** the generated file, **when** a developer reads it, **then** the authorize and
  audit seams are present as clearly marked editable points.
- **Given** the generated file, **when** the app wires the seams to its real stack, **then**
  concrete tools subclass `ApplicationMcpTool` and inherit those seams.

### R8 — Install generator (`rails g rails_mcp:install`, Devise-style)

`rails g rails_mcp:install` scaffolds everything an app needs to start, following the
Devise `devise:install` pattern. It creates: the app-owned `ApplicationMcpTool` (R7), a
`/mcp` route mount via `mount_mcp` (R6), an initializer, one read-only example tool, and
example tests (authz denial, audit-row-written).

- **Given** a Rails app with the gem, **when** `rails g rails_mcp:install` runs, **then**
  `app/mcp/application_mcp_tool.rb`, an initializer, a `/mcp` route line, one read-only
  example tool, and example tests are created.
- **Given** the generator ran, **when** the app boots, **then** the `/mcp` route is mounted
  and the example tool is registered.
- **Given** the generated example tests, **when** run, **then** they express authorization
  denial and audit-row-written as the expected safety checks.

**DECIDED** generator output: tools under `app/mcp/` (`app/mcp/application_mcp_tool.rb`);
initializer `config/initializers/rails_mcp.rb`; example tool
`app/mcp/example_read_only_tool.rb`; example tests `test/mcp/` (or the app's test dir).

### R9 — Act-as-real-staff-user identity (app-side)

The gem is authz-agnostic: it passes a **context object** into each tool and calls the
`authorize` seam. Resolving that context to a **real staff `User`** — so the audit log
answers "which human," not "the AI" — is **app code** written in `ApplicationMcpTool` (and
the surrounding Rack/controller layer that validates the bearer token → `User`). v1 uses
act-as-staff-user; a separate service identity is rejected for v1.

- **Given** the gem, **when** a tool runs, **then** the gem has passed a context object into
  the tool and made the acting user available to `authorize` and to the notification
  payload — without the gem itself resolving or inventing an identity.
- **Given** the app's wiring, **when** a tool runs on behalf of staff user U, **then** the
  audit event attributes the call to U (not to a generic AI/bot identity).
- **Given** an invocation with no valid staff identity in context, **when** the tool runs,
  **then** it fails closed (per R3).

**DECIDED** context object is a gem-defined wrapper carrying `user:` (the acting staff user,
resolved app-side) and `args:`. It guarantees no tenant (ADR-0004: the gem has no tenant
concept) and never carries the raw bearer token. The app populates `user:` in the
Rack/controller layer that validates the token; the gem passes the wrapper to `authorize`
and the notification payload.

### R10 — Allow-list (AI can invoke only registered tools)

The only callable surface is the set of registered `RailsMcp::Tool` subclasses. There is no
generic executor, no console tool, no arbitrary-Ruby path. An AI client can invoke only
registered tools, each with only its declared args (R1).

- **Given** a set of registered tools, **when** the client lists tools, **then** only those
  tools appear.
- **Given** a `tools/call` naming a tool that is not registered, **when** received, **then**
  it is refused.
- **Given** the gem's public surface, **when** audited, **then** there is no tool that
  executes arbitrary Ruby / console input (the Rails-Active-MCP anti-pattern is absent).

### R11 — Tenant scoping is app-owned code (no gem tenant logic)

The gem is tenant-agnostic and never sees tenants. It does not presume the app is
multi-tenant. Where an app *is* multi-tenant, scoping is 100% app code in
`ApplicationMcpTool`: the context carries the target tenant, tool bodies run inside the
app's scope (e.g. `tenant.with_shard { ... }`) and query through the tenant, never global
models. A tool that takes `tenant_id` as a free, unauthorized arg is a highest-severity
defect the app must prevent — but that is the app's concern, not the gem's.

- **Given** the gem source, **when** audited, **then** it contains no tenant/shard concept
  (no `with_shard`, no tenant model reference).
- **Given** a multi-tenant app, **when** it wires scoping in `ApplicationMcpTool`, **then**
  a cross-tenant-denial test (app-provided, not gem-shipped) can fail if a staff user
  reaches a tenant they may not act on.
- **Given** an `ApplicationMcpTool` wired with tenant scoping, **when** a tool runs, **then**
  the tenant comes from the authenticated context (not a free tool arg) and the tool body
  executes within that tenant's scope.

**DECIDED** the gem provides **no** tenant seam — no `around`/scope hook, no tenant concept
at any level. The gem's only frozen seams are `authorize` (R3) and the notification event
(R4). Tenancy, if the app has it, is ordinary app code the implementor writes inside
`perform`/`ApplicationMcpTool` using its own stack. Many target apps are not multi-tenant;
the gem must not presume tenancy exists.

### R12 — Adopt the official `mcp` gem for protocol plumbing

`rails_mcp` depends on the official `mcp` gem and does not reimplement JSON-RPC, the Rack
transport, tool schemas, or annotations. Protocol behavior is delegated upstream.

- **Given** the gemspec, **when** inspected, **then** the official `mcp` gem is a declared,
  pinned dependency.
- **Given** the gem source, **when** audited, **then** it contains no hand-rolled JSON-RPC
  or transport implementation — those come from `mcp`.

**DECIDED** engine is the official `mcp` gem (`modelcontextprotocol/ruby-sdk`). No
`action_mcp` spike — the README already settled this, and `action_mcp`'s Ruby 3.4.8+ floor
conflicts with the broadened 3.2+ target.

---

## Non-goals (restated as guardrails)

- No console/`rails runner` re-exposure (R10).
- No god-tool / generic executor (R10, over-broad-scope risk).
- No gem-side audit, permission, or tenant implementation (ownership boundary).
- No bearer tokens in logs or notification payloads (R4).
