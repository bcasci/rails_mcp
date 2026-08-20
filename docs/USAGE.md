# USAGE — installing `rails_mcp` and writing a tool

`rails_mcp` exposes a hand-picked allow-list of your Rails app's actions to an AI
client over MCP, on top of the official `mcp` gem. It ships the tool DSL and two seams
(`authorize` and the `invoke.rails_mcp` audit event); **your app owns** authorization, audit
persistence, and identity (ADR-0004). The gem is a neutral conduit (ADR-0012): a tool's
`perform` may read or write — the app decides; the gem gates nothing. `read_only!` is an
optional advisory annotation, not a mandate.

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
| `app/controllers/mcp_controller.rb` | the HTTP entry point in front of `/mcp`; **fail-closed** authentication seam (ADR-0008) |
| `app/mcp/registered_tools.rb` | the app-owned `RegisteredTools` list — `.all` returns the array of tool classes the AI may call (the allow-list) |
| `config/initializers/rails_mcp.rb` | points at the audit subscribe seam (the tool list lives in `RegisteredTools`, not here) |
| `test/mcp/example_read_only_tool_test.rb` | example safety tests: authz denial + one audit event |
| `config/routes.rb` | gains the `/mcp` route to `McpController#handle` |

As stamped the install **fails closed at two layers**: `McpController#authenticate_acting_user!`
raises, so `/mcp` denies every request until you wire authentication; and
`ApplicationMcpTool#authorize` raises, so every tool call is denied until you wire your real
check. That is intentional — a misconfigured install denies rather than exposes.

---

## 1a. Secure the HTTP entry point — `McpController` (required)

The generator routes `/mcp` to an **app-owned** `McpController < ApplicationController`
(`app/controllers/mcp_controller.rb`), not a direct transport mount. This is the app-owned
place to authenticate the HTTP request and resolve the acting `User` — whatever identity your
app resolves — **before any tool runs** (ADR-0008). The gem ships no authentication (ADR-0004);
it defines *where* auth goes, you define *what* it is.

A single `handle` action serves every MCP request verb. It authenticates the request, resolves
the acting user, then serves it on the official `mcp` gem's **public per-request pattern**: it
builds a **fresh `MCP::Server`** carrying `user` on `server_context`, wraps it in the stateless
`StreamableHTTPTransport`, and renders the Rack triple that `handle_request(request)` returns.
No gem call sits between the controller and `mcp` — the tool source and the transport are
visible, editable lines you own.

This is the hardened controller the generator stamps — edit the generated
`app/controllers/mcp_controller.rb` in place; do not hand-copy a simplified version that drops
the `skip_forgery_protection` and `allowed_hosts:` hardening below:

```ruby
class McpController < ApplicationController
  # CSRF is a browser defense; an MCP client is a machine sending a cookieless JSON
  # POST with no CSRF token. Turn it off for this machine endpoint and rely on the
  # authentication seam below instead.
  skip_forgery_protection

  def handle
    user = authenticate_acting_user!

    # A FRESH server per request, carrying `user` on server_context — never a
    # shared, process-wide server mutated per request. `RegisteredTools.all` is
    # the app-owned allow-list (app/mcp/registered_tools.rb); resolved here per
    # request so it always names the current, reloaded tool classes. Swap it for
    # another array to serve a different tool set on this route.
    server = MCP::Server.new(
      name: "rails_mcp",
      tools: RegisteredTools.all,
      server_context: {user: user}
    )

    # `allowed_hosts:` widens the SDK's DNS-rebinding guard beyond loopback to YOUR
    # app's host allow-list, so a real production Host is not rejected with
    # `403 Forbidden: Invalid Host header`. We pass only the String entries of
    # config.hosts. Add `allowed_origins:` / `dns_rebinding_protection:` for your deploy.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      allowed_hosts: Rails.application.config.hosts.grep(String)
    )
    status, headers, body = transport.handle_request(request)

    # Render the Rack triple back through the controller. Customize rendering here.
    headers.each { |key, value| response.headers[key] = value }
    self.response_body = body
    self.status = status
  end

  private

  # Fail-closed by default: as stamped this RAISES, so /mcp denies until you wire it.
  # Replace the raise with your app's real check (Devise, a session, a bearer token):
  #
  #   def authenticate_acting_user!
  #     authenticate_user!   # your ApplicationController auth
  #     current_user         # the resolved acting user your app resolves
  #   end
  def authenticate_acting_user!
    raise RailsMcp::NotAuthorized, "unauthenticated until secured"
  end
end
```

Building the `MCP::Server` **per request** with `user` on `server_context:` at construction
is what keeps identity thread-safe under Puma: two concurrent requests build two servers, so
neither can see the other's user (ADR-0008). The resolved `user:` is the only identity handed
to the gem; the raw request and any bearer token never reach `server_context` or the audit
payload.

Because `McpController` inherits your `ApplicationController`, it reuses your existing auth
stack. The `/mcp` endpoint is **unauthenticated until you secure it here** — wire real auth in
`authenticate_acting_user!` before exposing the endpoint.

---

## 2. Wire the two seams

Both seams and their frozen contracts are in [`SEAMS.md`](SEAMS.md). In brief:

### Authorization (`app/mcp/application_mcp_tool.rb`)

Replace the stamped raise with your real check. The signature is frozen —
`authorize(user:, args:, tool:)`; keep `**` for forward-compatibility:

```ruby
class ApplicationMcpTool < RailsMcp::Tool
  def authorize(user:, args:, tool:, **)
    raise RailsMcp::NotAuthorized, "no acting user" if user.nil?
    raise RailsMcp::NotAuthorized unless Pundit.policy!(user, tool).invoke?
  end
end
```

`user` is the identity your app resolved (from the bearer token or your own auth stack) and
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

## 2a. Make your first call (install → a proven `tools/call`)

This is the copy-paste path from a stamped install to a real MCP tool result over HTTP. It wires
the **static Bearer** example the generator ships commented in `mcp_controller.rb` — the
`find_by(api_token_digest: Digest::SHA256.hexdigest(token))` lookup — and then runs the
JSON-RPC handshake with `curl`.
Everything here is **host-app** setup (a migration, a seed, seam overrides); the gem
ships no auth or policy (ADR-0004), only the seams these steps fill.

> **Client-auth reality (read first).** v1 is a **static `Authorization: Bearer` token over
> Streamable HTTP** — validate it with `curl` (below) or an MCP inspector that lets you set a
> custom header. Claude's hosted remote-MCP connector expects **OAuth 2.1**, so a static Bearer
> from that surface is not guaranteed to connect; use `curl`/an inspector to prove the endpoint.

### 1. Add the `api_token_digest` column the bearer example reads

The stamped bearer path resolves the user by the **SHA-256 digest** of the token, stored
in an `api_token_digest` column on `users` — never the raw token. Storing the digest (not
the secret) is the constant-time-safe form: an equality match on the digest column never
compares the raw token, and a leaked database row never yields a usable token. Add the
column:

```console
$ rails g migration AddApiTokenDigestToUsers api_token_digest:string:index
$ rails db:migrate
```

The generated migration:

```ruby
class AddApiTokenDigestToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :api_token_digest, :string
    add_index :users, :api_token_digest
  end
end
```

### 2. Seed a token

The stamped example resolves the acting user by the SHA-256 digest of the token — any user
with a token can call. The gem takes no position on *who* may call; if you want to restrict it,
add a scope that fits your app and resolve through it (an example `staff` scope):

```ruby
# app/models/user.rb — OPTIONAL: only if you want to restrict which users get a token
class User < ApplicationRecord
  scope :staff, -> { where(staff: true) }
end
```

Seed a user with a random token, store only its digest, and print the **raw** token once
(you paste it into the `curl` calls below):

```ruby
# rails runner, a seed, or the console:
user  = User.first || User.create!(email: "operator@example.com")
token = SecureRandom.hex(24)                              # the raw token — shown once
user.update!(api_token_digest: Digest::SHA256.hexdigest(token))  # store the DIGEST, not the token
puts token   # copy this — it is your Bearer token; treat it like a password, never log it
```

`SecureRandom.hex(24)` is a 48-char random token. Treat it like a password — never log it.
The database stores only its SHA-256 digest, so a leaked row never yields a usable token.

### 3. Wire the two fail-closed seams to permit that user

Two seams are **fail-closed as stamped** — until both permit the acting user, the first call is
denied. Wire them:

**Authentication** — in `app/controllers/mcp_controller.rb`, replace the raising
`authenticate_acting_user!` with the bearer example the template already documents in a comment:

```ruby
def authenticate_acting_user!
  # Anchored scheme parse — requires the `Bearer ` prefix; never a global `.remove`.
  token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
  # Digest at rest: look up by the SHA-256 digest, never a raw `api_token` column.
  user = User.find_by(api_token_digest: Digest::SHA256.hexdigest(token)) if token
  raise RailsMcp::NotAuthorized, "no acting user" if user.nil?
  user
end
```

**Authorization** — in `app/mcp/application_mcp_tool.rb`, the stamped `authorize` **raises**
(the gem default denies). Override it to permit the resolved acting user, or the first
`tools/call` is blocked by the fail-closed `authorize` even after authentication succeeds:

```ruby
def authorize(user:, args:, tool:, **)
  raise RailsMcp::NotAuthorized, "no acting user" if user.nil?
  # permit the acting user your app resolved (replace with your real policy, e.g. Pundit)
end
```

The shipped example tool is already on the allow-list: the generator seeds `ExampleReadOnlyTool`
in `RegisteredTools.all` (`app/mcp/registered_tools.rb`), the app-owned list the controller hands
`MCP::Server.new(tools:)`. Nothing to do here for the example — you add your own tools by adding
their classes to that array:

```ruby
# app/mcp/registered_tools.rb
module RegisteredTools
  def self.all
    [
      ExampleReadOnlyTool
    ]
  end
end
```

### 4. Run the JSON-RPC handshake with `curl`

Start the app (`rails s`), export your token, then run the three requests against `POST /mcp`.
The route is `match "/mcp", to: "mcp#handle"` — every verb hits the one `handle` action.

Every request sends `Accept: application/json, text/event-stream` — the transport negotiates
its response type against that header, and a bare `Accept: application/json` can be refused. The
handshake is ordered: send `initialize` **first**. If a bare `tools/call` returns a
`"Server not initialized"` error, you skipped `initialize` — send the `initialize` request below
first, then retry the call.

```console
$ export TOKEN=<the api_token you printed above>
```

**`initialize`** — opens the session:

```console
$ curl -sS http://localhost:3000/mcp \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
```

**`tools/list`** — lists the allow-list; `example_read_only` appears:

```console
$ curl -sS http://localhost:3000/mcp \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

```json
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"example_read_only","description":"Example read-only diagnostic tool — replace with a real one.","inputSchema":{"type":"object","properties":{"subject":{"type":"string","description":"what to look up"}},"required":["subject"]},"annotations":{"readOnlyHint":true}}]}}
```

**`tools/call`** — invokes `example_read_only` and returns a real tool result:

```console
$ curl -sS http://localhost:3000/mcp \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"example_read_only","arguments":{"subject":"first call"}}}'
```

```json
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Looked up: first call"}],"isError":false}}
```

That `"Looked up: first call"` is `ExampleReadOnlyTool#perform` running through the gem's
authorize + audit pipeline — install to a proven `tools/call`. Now replace `ExampleReadOnlyTool`
with a real tool for your domain (section 4).

---

## 3. List your tools (the allow-list)

The AI can list and call **only** the tools in `RegisteredTools.all` — there is no generic
executor, no console tool, no arbitrary-Ruby path (R10). `app/mcp/registered_tools.rb` is
app-owned and editable; it is the **one place** naming what the AI may call. Add a tool by
adding its class to the array:

```ruby
# app/mcp/registered_tools.rb
module RegisteredTools
  def self.all
    [
      ExampleReadOnlyTool,
      Households::LookupTool
    ]
  end
end
```

The controller hands `RegisteredTools.all` to `MCP::Server.new(tools:)` per request, so the
array **is** the allow-list — that guarantee is the `mcp` gem's: it stores only the tools it is
given and refuses any `tools/call` for a name not in the set. A tool you never add to the list
is never callable; nothing is exposed until you list it.

---

## 4. Write a tool

Subclass `ApplicationMcpTool` so the tool inherits your authorize + audit seams. Name it for
the action it exposes in your domain vocabulary — a reviewer reading the class name must know
exactly what the AI can do. The tool below is a read-only example (it calls the optional
`read_only!` annotation); a write tool is the same shape minus `read_only!` — the gem runs
whatever `perform` does and gates nothing.

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
    # Resolve with find_by and raise a GENERIC message — never Model.find(id).
    # Any message you raise surfaces VERBATIM to the AI client (see "errors" below),
    # and find's RecordNotFound would leak the looked-up id into that message.
    household = Household.find_by(id: household_id)
    raise RailsMcp::NotAuthorized, "not found" if household.nil?
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
  the return value is the tool result. `perform` may read or write — the gem runs it either way
  and imposes no read/write policy (ADR-0012).
- `text_response("ok")` builds a text content result equal to `"ok"`.
- If `perform` raises, the error is surfaced as a tool error and the audit event records it.
- **The raised message reaches the AI client VERBATIM** (SEC-02) — the mcp gem sends
  `Internal error calling tool <name>: <e.message>` straight to the caller. So **raise
  generic messages** and resolve records with `find_by` + your own generic error, **never
  `Model.find(id)`** (its `RecordNotFound` leaks the looked-up id into that message). Never
  interpolate a record id, SQL, or an internal class name into a message you raise. Keep
  developer detail off the message — the audit `error:` payload carries the whole exception
  (e.g. `RailsMcp::NotAuthorized#detail`) for your logs.

### Annotations (R5)

- `read_only!` advertises `readOnlyHint: true` to the client (and clears the dangerous
  `destructiveHint` default).
- A tool that declares **no** annotation is treated as maximally dangerous — it is not
  silently marked read-only. Annotations are advisory hints the client MAY honor; never a
  server-side gate.

---

## 5. Customize the controller (app-owned seams) — R4

`McpController` is app-owned and inline (section 1a): the tool source and the transport
construction are **visible, editable lines**, not hidden behind a gem call. That is the
extension model — get specific in the controller without fighting the gem (ADR-0007). Three
common customizations:

### A different tool set per route

`RegisteredTools.all` is the default allow-list. To serve a different set on a given route,
hand `MCP::Server` a **different array** — a second `RegisteredTools`-style method, or a plain
inline `tools:` array:

```ruby
# A read-only subset for a public route — just a different array:
server = MCP::Server.new(
  name: "rails_mcp",
  tools: [Households::LookupTool],       # or RegisteredTools.public_subset
  server_context: {user: user}
)
```

Route two paths to two controllers (or two actions), each building its own server from its own
list, to expose different tool sets on different endpoints. The tool list is ordinary app
code — there is no gem registry to configure.

### Transport options

`StreamableHTTPTransport` takes the `mcp` gem's transport options — pass them where you build
the transport, for your real deploy:

```ruby
transport = MCP::Server::Transports::StreamableHTTPTransport.new(
  server,
  stateless: true,
  allowed_hosts: ["app.example.com"],
  allowed_origins: ["https://app.example.com"],
  dns_rebinding_protection: true
)
```

### Rendering

`handle_request` returns a Rack triple `[status, headers, body]`; the controller renders it.
Customize rendering there — add a response header, wrap the body, or branch on status:

```ruby
status, headers, body = transport.handle_request(request)

headers.each { |key, value| response.headers[key] = value }
response.headers["X-Request-Id"] = request.request_id   # your customization
self.response_body = body
self.status = status
```

All three are ordinary controller code in a file your app owns — the gem ships no boot-time
mount and no `serve` wrapper to reach around.

---

## 5a. Opting out — every convenience peels back to a raw `mcp` primitive (ADR-0007)

The gem is opinionated defaults, not a cage. Each convenience above yields to a lower-level
`mcp` primitive when you need to get specific — **document-only, no warning and no block**: an
opt-out is your informed choice, and the gem never nannies it (ADR-0007).

### A raw `input_schema` overrides the `arg` DSL

When you need a JSON Schema the `arg` DSL cannot express (a nested object, a `oneOf`, a pattern),
set the `mcp` gem's `input_schema` macro directly. The DSL **yields to it**: if you set a raw
`input_schema`, that is the advertised schema; the `arg` DSL builds one only when you use `arg`.
If you set both, the explicit `input_schema` wins.

```ruby
class Households::LookupTool < ApplicationMcpTool
  tool_name "households_lookup"
  # A raw schema — advertised as-is; the arg DSL is not consulted.
  input_schema(
    properties: {filter: {type: "object", properties: {status: {type: "string"}}}},
    required: ["filter"]
  )

  def perform(**args)
    text_response("...")
  end
end
```

### A raw `annotations` overrides `read_only!`

`read_only!` is shorthand for one annotation. To advertise other hints (or set them by hand),
call the `mcp` gem's `annotations` macro directly; the DSL yields to it.

```ruby
class Reports::ExportTool < ApplicationMcpTool
  tool_name "reports_export"
  annotations(read_only_hint: true, idempotent_hint: true)   # emitted as-is
end
```

### A raw `MCP::Tool` — outside the gem pipeline (unaudited, your choice)

List a plain `MCP::Tool` (not a `RailsMcp::Tool`) in `RegisteredTools.all` and it is listable
and callable like any other tool — but it runs **outside the gem's pipeline**: it gets **no
`authorize` seam and no `invoke.rails_mcp` audit event**, because those belong to
`RailsMcp::Tool`. The gem emits **no warning** — this is your informed, documented choice
(ADR-0007). The list is a plain array, so nothing distinguishes it from any other entry — you
own its safety.

```ruby
module RegisteredTools
  def self.all
    [ExampleReadOnlyTool, MyRawTool]   # MyRawTool runs unaudited — you own its safety
  end
end
```

If you want observability on a raw tool, use the `mcp` gem's own hooks — an
`around_request`/`exception_reporter` on your `MCP::Configuration` — rather than the gem's audit
event.

### A plain `tools:` array per endpoint

The tool list is ordinary app code — there is no gem registry. To serve a different tool set on
a route, hand `MCP::Server` a different array: a second `RegisteredTools`-style method or a plain
inline `tools:` array (section 5, "A different tool set per route"):

```ruby
MCP::Server.new(name: "rails_mcp", tools: [Households::LookupTool], server_context: {user: user})
```

None of these opt-outs triggers a warning, a deprecation, or a block. The gem documents the
seam; the app decides.

---

## 6. Test your tools

Every exposed tool needs two safety checks (the generator stamps examples):

- **Fails closed** without a real authorization pass (raises `RailsMcp::NotAuthorized`).
- **Emits exactly one** `invoke.rails_mcp` audit event per call, attributed to the acting
  user your app resolved.

See `test/mcp/example_read_only_tool_test.rb` from the generator for a working starting point.
