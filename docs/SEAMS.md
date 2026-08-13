# SEAMS — the frozen contracts

`rails_mcp` ships **no policy**. It defines exactly two seams and the context it hands them;
your app defines what they do (ADR-0004). These signatures are **frozen public API** — they
change only through a deprecation cycle, never a silent break. This document reflects the
seams **exactly as built**; the authoritative source is the code it points at.

The two seams are `authorize` (R3) and the `invoke.rails_mcp` notification event (R4). There
is no third seam.

---

## Client-auth reality (v1)

v1 authenticates each `/mcp` request with a static `Authorization: Bearer <token>` over
Streamable HTTP (ADR-0002/0003) — validate it with `curl` or an MCP inspector that accepts a
custom header. Claude's hosted remote-MCP connector expects OAuth 2.1, so a static Bearer from
that surface is **not guaranteed** to connect; v1 does not promise it. See the runnable
handshake in [`USAGE.md`](USAGE.md).

---

## The context handed to a tool

The gem never resolves, invents, or nil-checks an identity — that is app code. Your
Rack/controller layer validates the bearer token, resolves **the identity your app decides on
(a `User` or whatever your app uses)**, and puts it on the SDK's `server_context` when it
dispatches to `MCP::Server`. The gem reads `user` off that context and passes it into both
seams (R9); it takes no position on who that identity is.

In the generated default, that Rack/controller layer is the app-owned `McpController`
(ADR-0008): it authenticates each request, resolves the acting identity your app uses, then builds a **fresh
`MCP::Server`** on public `mcp` API with that user on `server_context:` at construction — for
that request only, never mutating a shared, process-wide server. The identity contract here
is **unchanged** (ADR-0005): the acting user still rides `server_context` and reaches
`authorize` / the audit payload exactly as below. `McpController` is only the app-owned place
that populates it per request; it adds no `authorize`/payload keys.

`server_context` may be either shape (`RailsMcp::Tool.call` accepts both — see
`lib/rails_mcp/tool.rb`):

- a Hash: `{ user: current_user }` (or whatever identity your app resolves)
- any object that responds to `#user` (including the SDK's `MCP::ServerContext`, which
  delegates `#user` to the underlying app context).

Guarantees (R9, ADR-0004):

- The context carries the acting **`user:`** (resolved app-side).
- It **never** carries the raw bearer token.
- An absent user is `nil`. The gem does not fail-closed on your behalf — your `authorize`
  denies a `nil` user.

---

## Seam 1 — `authorize` (R3, fail-closed)

Called **before** every `perform`, on every invocation. Frozen signature:

```ruby
def authorize(user:, args:, tool:)
```

| keyword | value |
|---------|-------|
| `user:` | the acting user resolved app-side (whatever identity your app resolves; may be `nil` if none) |
| `args:` | the declared args hash for this call (undeclared args already dropped) |
| `tool:` | the tool **instance** being invoked |

**Contract:**

- **Raise to deny, return to permit.** The default `authorize` in `RailsMcp::Tool` raises
  `RailsMcp::NotAuthorized` — an unconfigured install **fails closed** (denies). You override
  it in `ApplicationMcpTool`.
- `authorize` runs **before** any work in `perform`; on a denial `perform` never runs.
- Keep `**` in your override (`def authorize(user:, args:, tool:, **)`) so future context
  keys stay forward-compatible.

Denial error class: `RailsMcp::NotAuthorized < RailsMcp::Error` (`lib/rails_mcp/tool.rb`).
Raising it (or your own error) after the pipeline propagates it to the SDK as an
authorization error, and the one audit event still fires (recording the error).

Example override:

```ruby
def authorize(user:, args:, tool:, **)
  raise RailsMcp::NotAuthorized, "no acting user" if user.nil?
  raise RailsMcp::NotAuthorized unless Pundit.policy!(user, tool).invoke?
end
```

---

## Seam 2 — the `invoke.rails_mcp` notification (R4, audit)

The gem publishes **exactly one** `ActiveSupport::Notifications` event per tool invocation —
success, denial, or raise — and **persists nothing**. Your app subscribes and writes its own
audit row.

- **Event name:** `"invoke.rails_mcp"` — the single canonical name, defined once in code as
  the constant `RailsMcp::Instrumentation::EVENT`. Reference the constant; do not hardcode the
  string in more than one place (docs/conventions.md).

- **Payload** — exactly these keys, nothing else:

  | key | present | value |
  |-----|---------|-------|
  | `user:` | always | the acting user (the object handed in on the context) |
  | `tool:` | always | the tool name/class — the advertised `tool_name`, falling back to the Ruby class name |
  | `args:` | always | the declared args hash |
  | `result:` | success only | `perform`'s return value |
  | `error:` | failure only | the raised exception (a denial is a failure) |

  Exactly one of `result:` / `error:` is present. No other keys — the gem deliberately runs
  the block and captures the outcome before publishing, so
  `ActiveSupport::Notifications`'s own `:exception` / `:exception_object` keys never enter
  the payload (`lib/rails_mcp/instrumentation.rb`).

- **No credentials.** The payload and every gem log line exclude the bearer token and any
  credential — a standing rule guarded by CI grep (ADR-0004, R4).

Subscribe app-side (typically in `config/initializers/rails_mcp.rb`):

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

The row is attributed to the real human in `payload[:user]`, never to a generic AI/bot
identity (R9).

---

## What is deliberately NOT a seam

- **Audit persistence, permission model, identity resolution** — all app-owned. The gem
  defines *where* they happen (these two seams); the app defines *what* they are.

---

## The pipeline is an opinionated default, not a wall (ADR-0007)

The two seams above are what a **`RailsMcp::Tool`** gets: `authorize` before `perform`, then the
one `invoke.rails_mcp` event. That pipeline is an opinionated default, and every convenience
peels back to a raw `mcp` primitive when an app needs to get specific — the DSL yields to a raw
`input_schema`/`annotations`, `expose!` co-locates registration, and a per-endpoint registry or a
plain `tools:` array replaces `RailsMcp.registry`. Opting out is **document-only**: no warning, no
block (the how-to is [`USAGE.md` §5a](USAGE.md)).

The furthest opt-out is a **raw `MCP::Tool`** (not a `RailsMcp::Tool`) registered via the ordinary
`register`. It **sits outside this pipeline by design**: it runs and is listable, but it gets
**no `authorize` and no `invoke.rails_mcp` event** — those seams live on `RailsMcp::Tool`, and the
gem does not audit tools it does not own. That is the app's informed, documented choice; the gem
neither warns nor blocks (ADR-0004, ADR-0007).
