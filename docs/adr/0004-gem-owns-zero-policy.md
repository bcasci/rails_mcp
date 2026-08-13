# ADR-0004 — Gem owns zero policy; two seams only

Status: Accepted (2026-08-12)

## Context

Authorization, audit, identity, and tenancy are app-specific: every app has its own auth
stack (Pundit or otherwise), its own audit trail, its own idea of identity, and may or may
not be multi-tenant. A gem that ships opinions here fights the host app and presumes things
(like tenancy) that many apps do not have. The idea docs are explicit: the gem ships no
audit table, no permission model, no tenant logic (idea docs 01, 03, 08).

## Decision

The gem provides exactly two frozen seams:

1. `authorize` — called before `perform`, **fail-closed** by default (denies unless the app
   implements it).
2. one `ActiveSupport::Notifications` event per tool call — the gem publishes, the app
   subscribes and persists.

Everything else — staff-user resolution, audit persistence, and any tenant/shard scoping —
is ordinary app code the implementor writes in a generated, app-owned `ApplicationMcpTool`.
The gem has **no tenant concept** and does not presume the app is multi-tenant.

## Consequences

- The gem stays portable across any Rails app regardless of auth or tenancy model.
- The implementor owns security: they wire authz, audit, identity, and (if they have it)
  tenant isolation to their own conventions. This is a feature, not a gap.
- Fail-closed defaults mean a misconfigured install denies rather than exposes.
- The gem must be auditable as containing no policy, no tenant references, and no
  arbitrary-Ruby/console execution path.
