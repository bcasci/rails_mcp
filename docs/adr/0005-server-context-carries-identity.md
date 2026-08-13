# ADR-0005 — Acting identity rides the SDK's `server_context`, not a gem-defined wrapper

Status: Accepted (2026-08-12)

## Context

The gem is authz-agnostic: it must hand each tool an acting staff `User` that the app
resolved (from the bearer token) without the gem resolving or inventing identity (SPEC R9,
ADR-0004). The question is the **mechanism**: how the app-resolved user reaches
`authorize(user:, args:, tool:)` and the `invoke.rails_mcp` payload.

SPEC R9 pre-decided a gem-defined wrapper — "the context object is a gem-defined wrapper
carrying `user:` and `args:`." Building on the official `mcp` gem revealed that the SDK
already owns this exact seam: `MCP::Server` takes a `server_context`, and it threads it into
every tool as `Tool.call(**arguments, server_context:)`. Shipping a second, gem-defined
wrapper on top would duplicate the SDK's channel, add a class apps must learn, and put the
gem back in the business of defining a context type — friction ADR-0001 (delegate to the
SDK) and ADR-0004 (gem ships no policy, minimal seams) both argue against.

## Decision

The gem defines **no** context wrapper class. The acting user rides the official SDK's
existing `server_context`. The app populates it in the Rack/controller layer that validates
the bearer token (`server.server_context = {user: resolved_user}`); `RailsMcp::Tool.call`
reads the user out of it (`user_from`, tolerant of a Hash `{user:}`, an object responding to
`#user`, or `MCP::ServerContext`) and threads that `user:` — together with the declared,
allow-listed `args:` — into `authorize` and the audit event.

The **frozen contract is the keyword surface**, unchanged from R9/R3/R4: `authorize(user:,
args:, tool:)` and payload `{user:, tool:, args:, result|error}`. What changed is only the
transport of `user:` into the gem — the SDK's `server_context`, not a `RailsMcp`-owned
object. The raw bearer token stays in the app's auth layer and never enters `server_context`
or the payload (R4, R9).

This supersedes the R9 "gem-defined wrapper" mechanism only; every R9 guarantee (app resolves
identity, gem never invents it, no tenant, no raw token, fail-closed on absent user) holds.

## Consequences

- One identity channel, owned by the SDK — apps wire `server.server_context` the SDK's own
  way; no extra gem type to learn or version. Reinforces ADR-0001/ADR-0004.
- The `authorize`/payload keyword contract (the thing apps and subscribers actually depend on)
  is what stays frozen; the wrapper was never part of that surface.
- Identity resolution stays fully app-side: absent user is `nil`, and fail-closed is the
  app's `authorize` job (the gem never fabricates an identity).
- `docs/SEAMS.md` and the install generator's `ApplicationMcpTool` document `server_context`
  as the wiring point; there is no `RailsMcp::Context` to reference.
- Constraint: the gem must not grow a context/identity wrapper class — doing so re-forks this
  decision and would need a superseding ADR.
