# ADR-0007 — Convenience without lock-in

Status: Accepted (2026-08-13)

## Context

`rails_mcp` is a thin conventions-and-seams layer over the official `mcp` gem. Everything it
adds — the `arg`/annotations DSL, the `perform`/`authorize`/audit invoke pipeline, the
registry, the install generator, the `McpController` entry point — is **convenience plus
flexible wiring**. None of it is a capability that the `mcp` gem plus a diligent implementor
lacks: `mcp` already exposes tool `call`, per-request `server_context`, and observability
seams (`Configuration#around_request`, `#exception_reporter`); authentication and audit
persistence are the app's, always (ADR-0004). The risk is that an ergonomic default becomes a
cage — a convenience an app cannot peel back when it needs to get specific.

## Decision

Every convenience the gem adds is an **opinionated default the implementor can drop to the
underlying `mcp` seam**, for one tool, one endpoint, or one need, without abandoning the gem:

- **Args** — set a raw `input_schema` instead of using `arg`; the DSL yields to an
  explicitly-set schema. Same for `annotations` vs `read_only!`.
- **Tool behavior** — subclass a raw `MCP::Tool` and define `self.call` for a bespoke tool;
  register it like any other. It gets no `authorize`/audit (the pipeline lives in
  `RailsMcp::Tool`) — that is the app's informed choice, **documented, not warned or blocked**.
- **Observability** — beyond the `invoke.rails_mcp` notification, wire `mcp`'s own
  `around_request`/`exception_reporter`. Audit persistence is app-owned.
- **Authentication** — the generated `McpController` uses the app's own auth; the gem
  authenticates nothing.
- **Exposure** — register centrally, co-locate with `expose!`, use a per-endpoint
  `RailsMcp::Registry`, or pass a plain `tools:` array straight to `MCP::Server`.

The gem does **not** warn or raise when an implementor opts out of a convenience; it documents
the seam and stays out of the way. Opinionated defaults, never enforcement.

**One guardrail is not a convenience and does not relax: no auto-discovery of tools.** Exposure
is always an explicit act (`register` or `expose!`); the gem never auto-registers subclasses.
The allow-list is the product — "everything unless excluded" is never offered.

## Consequences

- An app can get arbitrarily specific by dropping to public `mcp` API at any single layer
  without forking or fighting the gem.
- The gem's surface stays small: it adds no capability it must then maintain against `mcp`
  changes; each convenience maps to a public `mcp` seam.
- Standing constraint (machine-checkable): tests prove a raw `MCP::Tool` can be registered and
  invoked; a custom `input_schema`/`annotations` survives on a `RailsMcp::Tool`; a per-endpoint
  registry and a plain `tools:` array both work. There is no code path that auto-registers a
  tool by mere subclassing.
- A future convenience that cannot be peeled back to an `mcp` seam, or that enforces rather
  than defaults, needs a superseding ADR — it violates this one.
