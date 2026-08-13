# ADR-0003 — Read-only v1 (no mutations)

Status: Superseded by [ADR-0012](0012-gem-is-a-neutral-mcp-conduit.md) (2026-08-13)

## Context

The idea replaces SSH + `rails runner`/console for production support: powerful,
unaudited, unscoped. The full vision includes mutating actions ("take action X"), but
mutations carry real blast radius and want human-in-the-loop approval, which is unbuilt.
Shipping read-only first is safer than console access the day it ships (idea docs 01, 05,
07).

## Decision

v1 registers and invokes **read-only diagnostic tools only**. No tool may mutate. The value
of v1 is allow-list + real-staff attribution + audit with near-zero blast radius.

Explicitly deferred to later phases: mutating tools (`destructiveHint: true`),
human-in-the-loop approval tiers, full OAuth 2.1 for third-party clients, and the second/
third app rollout.

## Consequences

- Small, safe first surface that proves the seams against one app before mutations exist.
- The tool base class still carries annotation and seam machinery so Phase 2 mutations slot
  in without redesign.
- Approval-flow seams may exist but no approval flow ships in v1.
