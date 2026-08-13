# USAGE — installing `rails_mcp` and writing a read-only tool

`rails_mcp` exposes a hand-picked allow-list of your Rails app's read-only actions to an AI
client over MCP, on top of the official `mcp` gem. It ships the tool DSL and two seams
(`authorize` and the `invoke.rails_mcp` audit event); **your app owns** authorization, audit
persistence, staff-user identity, and any tenant scoping (ADR-0004). v1 is **read-only** — no
tool may mutate (ADR-0003).

The frozen contracts (`authorize` signature, event name/payload, context shape) are specified
in [`SEAMS.md`](SEAMS.md). This document is the how-to.

---

## 1. Install

Add the gem:

```ruby
# Gemfile
gem "rails_mcp"
```

Then run the generator (Devise-style):

```console
$ bundle install
$ rails g rails_mcp:install
```

It stamps, all **app-owned and editable**:

| file | what it is |
|------|------------|
| `app/mcp/application_mcp_tool.rb` | your base tool (like `ApplicationController`); **fail-closed** authorize seam + audit note |
| `app/mcp/example_read_only_tool.rb` | one read-only example tool to copy |
| `config/initializers/rails_mcp.rb` | registers tools (the allow-list) and points at the audit subscribe seam |
| `test/mcp/example_read_only_tool_test.rb` | example safety tests: authz denial + one audit event |
| `config/routes.rb` | gains the `mount_mcp '/mcp'` line |

As stamped the install **fails closed**: `ApplicationMcpTool#authorize` raises, so every call
is denied until you wire your real check. That is intentional — a misconfigured install denies
rather than exposes.

---

## 2. Wire the two seams

Both seams and their frozen contracts are in [`SEAMS.md`](SEAMS.md). In brief:

### Authorization (`app/mcp/application_mcp_tool.rb`)

Replace the stamped raise with your real check. The signature is frozen —
`authorize(user:, args:, tool:)`; keep `**` for forward-compatibility:

```ruby
class ApplicationMcpTool < RailsMcp::Tool
  def authorize(user:, args:, tool:, **)
    raise RailsMcp::NotAuthorized, "no staff user" if user.nil?
    raise RailsMcp::NotAuthorized unless Pundit.policy!(user, tool).invoke?
  end
end
```

`user` is the real staff `User` your Rack/controller layer resolved from the bearer token and
put on the SDK's `server_context` — the gem never invents an identity (R9). Raise to deny,
return to permit; on a denial `perform` never runs.

### Audit (`config/initializers/rails_mcp.rb`)

The gem publishes exactly one `invoke.rails_mcp` event per call and persists nothing.
Subscribe and write your own row:

```ruby
ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*_args, payload|
  McpAuditLog.create!(
    user: payload[:user],
    tool: payload[:tool],
    args: payload[:args],
    outcome: payload.key?(:error) ? "error" : "ok"
  )
end
```

The payload is `{ user:, tool:, args: }` plus exactly one of `result:` / `error:` — and never
a bearer token or credential.

---

## 3. Register tools (the allow-list)

The AI can list and call **only** registered tools — there is no generic executor, no console
tool, no arbitrary-Ruby path (R10). Register each tool you expose in the initializer:

```ruby
Rails.application.config.to_prepare do
  RailsMcp.registry.register(Households::LookupTool)
end
```

A fresh registry is empty; nothing is callable until you register it. `tools/call` on an
unregistered tool is refused.

---

## 4. Write a read-only tool

Subclass `ApplicationMcpTool` so the tool inherits your authorize + audit seams. Name it for
the action it exposes in your domain vocabulary — a reviewer reading the class name must know
exactly what the AI can do.

```ruby
# app/mcp/households/lookup_tool.rb
class Households::LookupTool < ApplicationMcpTool
  tool_name "households_lookup"
  description "Look up a household by id (read-only diagnostic)."

  # Declare args by their domain concept, never :id or :param. Only declared args
  # reach perform; the AI cannot smuggle undeclared arguments.
  arg :household_id, :integer, required: true, description: "the household to look up"

  read_only!

  def perform(household_id:)
    household = Household.find(household_id)
    text_response("Household #{household.id}: #{household.name}")
  end
end
```

### The args DSL (R1)

```ruby
arg :name, :type, required: false, description: nil
```

- Each declared arg becomes part of the tool's MCP **input schema**; the official `mcp` gem
  validates required-ness and type against it (no hand-rolled type engine).
- A missing required arg or a wrong-typed arg is **rejected before `perform`**.
- **Only declared args reach `perform`** — an undeclared argument the AI sends is dropped
  (allow-list on args).
- Supported types: `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`. An
  unknown type is rejected at declaration time.

### `perform` and results (R2)

- Define behavior in `def perform(**declared_args)` — declared args arrive as keywords, and
  the return value is the tool result. **Read only in v1** — no writes.
- `text_response("ok")` builds a text content result equal to `"ok"`.
- If `perform` raises, the error is surfaced as a tool error and the audit event records it.

### Annotations (R5)

- `read_only!` advertises `readOnlyHint: true` to the client (and clears the dangerous
  `destructiveHint` default).
- A tool that declares **no** annotation is treated as maximally dangerous — it is not
  silently marked read-only. Annotations are advisory hints the client MAY honor; never a
  server-side gate.

---

## 5. Mount the endpoint (R6)

The generator adds this to `config/routes.rb`:

```ruby
mount_mcp '/mcp'
```

- Mounts the official gem's Rack transport in **stateless** HTTP mode (ADR-0002) in the same
  Rails process — no SSE, so no idle-timeout/thread-starvation. AI clients keep their own
  session state.
- `tools/list` returns only registered tools; `tools/call` on an unregistered tool is refused.
- Extra keyword args pass through to the transport, e.g. `mount_mcp '/mcp', allowed_hosts:
  ["app.example.com"], server_name: "myapp"`.

Your app is responsible for the Rack/controller layer that validates the bearer token,
resolves the staff `User`, and puts it on `server_context` before dispatch — that is what
makes `user` available to `authorize` and the audit event.

---

## 6. Tenancy (only if your app is multi-tenant) — R11

The gem has **no tenant concept** and does not presume you are multi-tenant. If you are,
scoping is ordinary app code you add in `ApplicationMcpTool` / `perform` — take the tenant
from the **authenticated context**, never a free tool arg, and run tool bodies inside its
scope:

```ruby
def perform(**args)
  current_tenant.with_shard { super }
end
```

A tool that accepts `tenant_id` as a free, unauthorized arg is a highest-severity defect your
app must prevent — the gem cannot, because it never sees tenants. If your app is single-tenant,
ignore this entirely.

---

## 7. Test your tools

Every exposed tool needs two safety checks (the generator stamps examples):

- **Fails closed** without a real authorization pass (raises `RailsMcp::NotAuthorized`).
- **Emits exactly one** `invoke.rails_mcp` audit event per call, attributed to the acting
  staff user.

See `test/mcp/example_read_only_tool_test.rb` from the generator for a working starting point.
