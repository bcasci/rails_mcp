# ADR-0010 — Tenancy is host-app business logic, off the gem surface

Status: Accepted (2026-08-13)

## Context

The gem accumulated tenancy/sharding teaching across templates, docs, and fixtures — a
`Current.tenant.with_shard` block in the generated controller, a `TENANT SCOPING` section in
`ApplicationMcpTool`, a USAGE "Tenancy" tutorial, and a sharded-tenant fixture with tests.
`rails_mcp` ships **zero** tenant concept (ADR-0004). Tenancy is host-app business logic in the
same category as caching or rate limiting, which the gem never mentions. R11 in spec 0001 was a
*disclaimer* ("the gem has no tenant concept"); subsequent specs drifted from disclaiming it to
demonstrating it, importing an app concern the gem must not own.

## Decision

The gem ships **no** tenancy/shard/multitenancy content on its surface — not in `lib/`, the
generated templates, `README`, `USAGE`, `SEAMS`, `conventions`, or `generators`. The only
tenancy-adjacent fact kept is neutral and tenancy-free, a property of the gem's own pipeline:
`authorize` runs before `perform` in the invoke pipeline, so to run a whole call inside an
app-established request-scoped context, wrap `handle_request` at the controller (a wrapper
around `perform` alone runs too late). No tenant example illustrates it.

The immutable ADR-0004 (gem owns zero policy) and ADR-0005 (identity on `server_context`) and
their "no tenant" boundary statements are unchanged — this ADR complements, it does not rewrite.

## Consequences

- The gem's surface matches its scope: convenience + wiring over `mcp`, no host-app domain.
- Apps do tenancy the way they do any request scoping — their own code, wrapped where they
  choose (the controller is a documented, generic option).
- Standing constraint (machine-checkable): `grep -ri 'tenant\|shard\|multitenan'` over `lib/`,
  `docs/` (excluding `docs/adr/`), and `README.md` returns nothing.
- The neutral authorize-before-perform ordering fact is retained as the one legitimate
  gem-level statement, with no tenancy framing.
