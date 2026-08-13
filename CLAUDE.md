# rails_mcp — agent working notes

A Ruby gem exposing selected Rails app actions to an AI client over MCP, on top of the
official `mcp` gem. The gem ships conventions and seams only; each app owns authorization,
audit, and (if it has it) tenancy. See `SPEC.md` (build contract), `TICKETS.md` (build
breakdown), and `docs/adr/` (decisions).

## Building (the factory)

- Implement tickets with the `spec-driven-dev` skill: read the ticket + its SPEC
  requirements, test-first from the acceptance criteria, implement to green, run the gate.
- `/implement` (`.claude/workflows/implement.js`) runs the whole build: builder agents per
  ticket in dependency order, a per-layer gate + heal loop, an integration audit, and a
  reflect stage. `/implement T3` builds one ticket.
- Review is a separate pass by a different agent: `/code-review --fix`, guided by
  `REVIEW.md`. Never self-certify.
- Naming/architecture/testing rules: `docs/conventions.md`. Generator specifics:
  `docs/generators.md`.

## Recording decisions and learnings

A `Stop` hook nudges once per session to record durable knowledge. Route it:

- **Decision** — architecturally significant and hard to reverse: a new/replaced
  dependency, a change to a public seam (`authorize`, the notification payload,
  `mount_mcp`), or a structural choice. → Write an **ADR** in `docs/adr/`, numbered, using
  the Nygard template (Status / Context / Decision / Consequences). Write it at decision
  time, not reconstructed. ADRs are immutable once Accepted — to change one, add a new ADR
  that supersedes it and link both ways.
- **Convention or gotcha** specific to this gem → add a line here.
- **Cross-project or behavioral** learning → user-local memory, not this repo.

No learnings bank yet — record straight to the primitive above. Add a bank only if
recurring gotchas start accumulating across the multi-app rollout.

### Machine-checkable ADR constraints

Some ADRs are standing constraints, enforced by grep in CI (not just prose):

- ADR-0001 / ADR-0004 — no hand-rolled JSON-RPC/transport, no console or arbitrary-Ruby
  tool, no gem-side policy or tenant references.

## Conventions

Project-specific naming, architecture invariants, layout, and API rules are in
[`docs/conventions.md`](docs/conventions.md) — read it before adding classes or seams.
Baseline: minitest, standardrb, read-only v1 (ADR-0003).
