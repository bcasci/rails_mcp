# ADR-0001 — Adopt the official `mcp` gem for protocol plumbing

Status: Accepted (2026-08-12)

## Context

MCP needs JSON-RPC handling, a Rack/HTTP transport, tool schema advertisement, and
annotations. Building these by hand is undifferentiated work and a maintenance liability.
The landscape survey (idea doc 02) found the official `modelcontextprotocol/ruby-sdk`
(`mcp` gem) covers this layer, and flagged `action_mcp` as a batteries-included alternative
(Gateway/consent/session) worth a possible spike.

## Decision

Depend on the official `mcp` gem and delegate all protocol behavior to it. `rails_mcp`
reimplements none of JSON-RPC, transport, schemas, or annotations. No `action_mcp` spike:
its Ruby 3.4.8+ floor conflicts with our broadened 3.2+ target (ADR-0002 chain), it runs
standalone rather than mounted, and the official SDK already covers v1's needs.

## Consequences

- `rails_mcp` stays thin — conventions and seams only (see ADR-0004).
- We inherit the official SDK's release cadence and any protocol-conformance fixes.
- Annotation emission depends on the pinned `mcp` version actually supporting it
  (SDK issue #259) — verify the pinned version during the build.
