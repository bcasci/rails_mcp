# SPEC — strip tenancy from the shipped surface

Build contract for spec 0006: remove all tenancy/shard teaching from the gem's shipped surface,
keeping exactly one neutral, tenancy-free pipeline-ordering fact, and drop the tenancy-only
tests and the orphaned `dummy_app` fixture — without losing any non-tenancy behavioral
coverage. Builds on shipped specs 0001–0005 (archived). Requirements are testable; acceptance
criteria are Given/When/Then.

All decisions are settled — `DECIDED` marks each. Governing decision: **ADR-0010** (tenancy is
host-app business logic, off the gem surface). Unchanged and immutable: ADR-0004 (zero policy),
ADR-0005 (identity), and their "no tenant" boundary statements — do not rewrite them.

---

## Background

Tenancy drifted from a one-line disclaimer (R11) into demonstrations: a `with_shard` block in
the controller, a `TENANT SCOPING` section in `ApplicationMcpTool`, a USAGE tenancy tutorial,
and a sharded fixture. That is host-app domain the gem must not teach (ADR-0010). This spec
removes it. Two consistency fixes ride along: the orphaned `test/integration/dummy_app/`
(superseded by `fixture_app` in spec 0005) and stale `mount_mcp` references in `docs/`
(removed in ADR-0008).

---

## Scope

### In this spec

- Remove tenancy content from `lib/rails_mcp.rb`, the generated templates, `README.md`,
  `docs/USAGE.md`, `docs/SEAMS.md`, `docs/conventions.md`, `docs/generators.md`, and
  `install_generator.rb`.
- Keep exactly one neutral fact: `authorize` runs before `perform`; wrap `handle_request` at
  the controller to scope a whole call. No tenant/shard words.
- Remove tenancy-only tests and fixtures; keep every non-tenancy behavioral test green.
- Delete the orphaned `test/integration/dummy_app/`; fix stale `mount_mcp` doc references.

### Out of scope

- The Getting-started recipe — spec 0007.
- Any gem runtime behavior change (authorize, payload, controller pattern, registry) — none.
- Immutable ADRs 0004/0005 — untouched.

**DECIDED** the neutral replacement text for the controller's scoped-context comment is
tenancy-free: it states only that `authorize` precedes `perform` and that a whole-call scope
wraps `handle_request` (ADR-0010).

**DECIDED** `test/integration/real_world_hardening_test.rb` is edited **surgically** — remove
only the shard classes/constants (`DOCUMENTED_SHARD_WRAP`, `ShardObservingTool`,
`ShardWrappingController`), the two shard tests, **and the shard references in the shared
`setup` block** so the kept tests do not raise `NameError`. Keep the CSRF, Host-guard (both
directions), reload, and fail-closed tests. The file is not deleted.

**DECIDED** the `lib/rails_mcp.rb` header drops "and any tenant scoping" while keeping the
`(ADR-0004)` reference verbatim.

---

## Requirements

### R1 — No tenancy on the shipped surface

- **Given** the shipped surface, **when** `grep -ri 'tenant\|shard\|multitenan'` runs over
  `lib/`, `docs/` (excluding `docs/adr/`), and `README.md`, **then** it returns nothing.
- **Given** `lib/rails_mcp.rb` and `docs/USAGE.md` intro, **when** read, **then** neither says
  "and any tenant scoping" (both carried it); the `(ADR-0004)` reference stays.

### R2 — The neutral pipeline-ordering fact is kept, tenancy-free

- **Given** the stamped `mcp_controller.rb.tt`, **when** read, **then** it documents that
  `authorize` runs before `perform` and that a whole-call request-scoped context wraps
  `handle_request`, with **no** `tenant`/`shard`/`Current.tenant` words.
- **Given** `ApplicationMcpTool` template, **when** read, **then** the `TENANT SCOPING` section
  is gone and no tenancy how-to remains.

### R3 — Immutable ADRs and frozen behavior untouched

- **Given** `docs/adr/0004-*.md` and `docs/adr/0005-*.md`, **when** compared, **then** they are
  byte-for-byte unchanged.
- **Given** the gem runtime (authorize signature, `invoke.rails_mcp` payload, controller
  pattern, registry keyed by `tool_name`), **when** the suite runs, **then** all are unchanged.

### R4 — No non-tenancy behavioral coverage lost

- **Given** the test suite after the strip, **when** run, **then** it is green, and these still
  pass: cookieless-POST-behind-`protect_from_forgery` (CSRF), production-host-passes +
  unlisted-host-403s (Host guard), reload-does-not-`ToolNotUnique`, fail-closed-seam, and the
  frozen-signature/payload/identity/allow-list/read-only tests.
- **Given** the removed tests, **when** audited, **then** only tenancy-only tests were dropped
  (`tenant_guidance_docs_test.rb` in full; the two shard tests in
  `real_world_hardening_test.rb`; the tenancy template-string tests in
  `install_generator_test.rb` — keeping its host-guard tests).

### R5 — Orphaned fixture removed; stale doc references fixed

- **Given** `test/integration/`, **when** listed, **then** `dummy_app/` is gone and nothing
  requires it (`fixture_app/boot.rb` no longer references it).
- **Given** `docs/SEAMS.md`, `docs/conventions.md`, and `docs/generators.md`, **when** read,
  **then** there is no reference to the removed `mount_mcp`/`RailsMcp.serve`/`rack_app`
  symbols; the seam list names only `authorize` and the `invoke.rails_mcp` event, and the
  route guidance targets `mcp#handle`.

---

## Non-goals (guardrails)

- No gem runtime change; strip is templates/docs/tests only.
- No rewrite of immutable ADRs 0004/0005 (R3).
- No new tenancy framing anywhere — the one kept fact is tenancy-free (R2).
