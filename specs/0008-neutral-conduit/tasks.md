# TASKS — de-opinion the gem surface (neutral MCP conduit)

Task breakdown for spec 0008. Each task owns a DISJOINT set of files. Docs/templates/comments
only — no gem runtime change (R6). Builds on shipped specs 0001–0007 (archived). Governing
decision: ADR-0012. References like `R1` point to this spec's `spec.md`.

Every task is `autonomous`. T1–T3 are independent (disjoint files), parallel; T4 gates.

---

## Layer 0 — Strip posture + neutralize framing (parallel)

### T1 — Annotations comment + example tool/tests
**Owns:**
- `lib/rails_mcp/annotations.rb` (CHANGED: the comment no longer says "v1 is read-only
  (ADR-0003)"; `read_only!` stays exactly as an optional advisory annotation — code unchanged)
- `lib/generators/rails_mcp/install/templates/example_read_only_tool.rb.tt` (CHANGED: keep it as
  a read-only *example* but drop the "v1 is read-only … must not mutate anything" mandate; note
  `read_only!` is an optional annotation and a write tool simply omits it)
- `lib/generators/rails_mcp/install/templates/example_tests.rb.tt` (CHANGED only if it asserts
  read-only-as-mandate; keep the authz/audit example assertions)
- `test/rails_mcp/annotations_test.rb` (CHANGED: confirm `read_only!` still advertises
  `readOnlyHint: true`; no posture assertions)

**Depends on:** shipped.
**Acceptance (R1, R2):** no read-only mandate in these files; `read_only!` still works.
**Tag:** `autonomous`.

### T2 — Docs: README, USAGE (incl §1a fix + curl note), SEAMS, conventions
**Owns:**
- `README.md` (CHANGED: remove read-only/staff/internal posture; the gem exposes app-defined
  tools, read or write, the app decides)
- `docs/USAGE.md` (CHANGED: remove read-only posture and "staff/internal" framing → "the
  identity your app resolves"; **fix §1a** so its controller example matches the hardened
  stamped controller — `skip_forgery_protection` + `allowed_hosts:` — or points at the generated
  file; **add the curl note** — `Accept: application/json, text/event-stream`, and
  `initialize`-first if a bare `tools/call` returns "not initialized")
- `docs/SEAMS.md` (CHANGED: neutralize "staff"/"which human" identity framing; the seams and
  payload keys are unchanged)
- `docs/conventions.md` (CHANGED: remove any read-only-v1 / staff framing; keep the naming,
  architecture, and integration-reality rules)

**Depends on:** shipped. Independent of T1/T3.
**Acceptance (R1, R3, R4, R5):** posture gone; identity framing neutral; §1a matches the stamped
controller; curl note present.
**Tag:** `autonomous`.

### T3 — Templates: controller + base tool + generator desc
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED: neutralize
  "acting staff user" → "the acting user your app resolves"; keep every hardening line
  (`skip_forgery_protection`, `allowed_hosts:`, the auth seam) unchanged)
- `lib/generators/rails_mcp/install/templates/application_mcp_tool.rb.tt` (CHANGED: neutralize
  "staff user" / "which human" framing in comments; `authorize(user:, args:, tool:)` unchanged)
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED only if its desc/comments
  carry read-only/staff posture)
- `test/generators/install_generator_test.rb` (CHANGED only if a test asserts the removed
  posture strings; keep the hardening + fail-closed assertions)

**Depends on:** shipped. Independent of T1/T2.
**Acceptance (R3, R6):** neutral identity framing; no hardening or seam behavior changed.
**Tag:** `autonomous`.

---

## Layer 1 — ADR status + gate

### T4 — Supersede ADR-0003; gate + posture-clean proof
**Owns:**
- `docs/adr/0003-read-only-v1.md` (CHANGED: `Status:` line → "Superseded by ADR-0012
  (2026-08-13)" with a bidirectional link; body unchanged — immutable)

**Depends on:** T1, T2, T3.
**Acceptance (R1, R6):**
- `bundle exec rake` (minitest + standardrb) is green.
- No read-only/mutation *mandate* remains on the shipped surface (`grep` over `lib/`, `docs/`
  excluding `docs/adr/`, `README.md` for "read-only v1", "must not mutate", "no tool may
  mutate", "v1 is read-only" returns nothing); advisory `read_only!` references are fine.
- ADR-0003 body is unchanged except its status line; ADR-0012 exists and is referenced.

**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0007)
T1 ┐
T2 ┼─→ T4
T3 ┘
```

T1–T3 parallel (disjoint files); T4 gates.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0012 — do not relitigate):**
- Read-only/staff/internal is posture, not code; strip it from the surface; `read_only!` stays
  as an optional advisory annotation.
- Identity framing is neutral ("the identity your app resolves"); `user:` keyword unchanged.
- §1a shows the hardened stamped controller; curl `Accept`/`initialize` note added.
- ADR-0003 status → superseded by ADR-0012; body immutable.
- No gem runtime/behavior change.

No open decisions remain — every task is `autonomous`.
