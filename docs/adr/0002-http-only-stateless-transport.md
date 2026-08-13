# ADR-0002 — HTTP-only, stateless transport for v1

Status: Accepted (2026-08-12)

## Context

MCP supports stdio and Streamable HTTP. The core use case is remote production support —
"go take action X for customer Y" against a deployed app on Fly (idea doc 04). stdio suits
local dev but not a remote endpoint. Stateful HTTP/SSE risks idle-timeout and
thread-starvation on Fly; the official SDK offers a stateless mode.

## Decision

v1 ships HTTP only, mounted at `/mcp` in the existing Rails process via a `mount_mcp` route
helper, running in the SDK's **stateless** mode. stdio is not shipped in v1. AI clients
maintain their own session state.

## Consequences

- One deploy: the MCP endpoint rides in the same Fly app as the web process — no separate
  service, no extra infra.
- Stateless survives restarts and multi-instance scaling; no server-side session store.
- Local-dev-over-stdio is deferred; developers exercise the endpoint over HTTP.
- Version floor is broadened to Ruby 3.2+ / Rails 7.1+ so apps older than the target set
  (Boswell, Rails 8.1.1 / Ruby 3.4.4) can still adopt the gem.
