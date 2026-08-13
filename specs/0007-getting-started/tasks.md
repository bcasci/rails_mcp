# TASKS — Getting started: install to first `/mcp` call

Task breakdown for spec 0007. Docs-only; no gem runtime change. Builds on shipped specs
0001–0006 (archived — tenancy already stripped, so the recipe reflects the post-strip surface).
References like `R1` point to this spec's `spec.md`. Run **after** spec 0006 (both edit
`USAGE.md`/`README.md`; 0006 strips, 0007 adds).

Every task is `autonomous` — decisions locked in spec.md.

---

## Layer 0 — The recipe

### T1 — Token setup + JSON-RPC handshake in USAGE, condensed in README
**Owns:**
- `docs/USAGE.md` (CHANGED: add a "Make your first call" section — the `api_token` migration,
  `SecureRandom.hex(24)` staff seed, `staff` scope, the note to override
  `ApplicationMcpTool#authorize` to permit staff, then the pasteable `curl` handshake
  `initialize` → `tools/list` → `tools/call example_read_only` with `Authorization: Bearer`)
- `README.md` (CHANGED: a condensed Getting-started — Gemfile git line, `rails g
  rails_mcp:install`, wire `authenticate_acting_user!`, curl `tools/call`)

**Depends on:** shipped 0001–0006.
**Acceptance (R1, R2):** token setup matches the stamped bearer example; the handshake uses the
real tool name `example_read_only` and `POST /mcp`; README carries the condensed form.
**Tag:** `autonomous`.

### T2 — Client-auth reality note + CHANGELOG
**Owns:**
- `docs/SEAMS.md` (CHANGED, only if the transport/first-call note fits there; else fold into
  USAGE under T1 — keep files disjoint: if T1 owns USAGE, T2 adds the note to SEAMS or README's
  note line. To stay disjoint, T2 owns the note in `docs/SEAMS.md` and the CHANGELOG.)
- `CHANGELOG.md` (CHANGED: `[Unreleased]` records the 0006 tenancy strip, `dummy_app` removal,
  doc seam/route corrections, and this recipe)

**Depends on:** shipped. Independent of T1 if the client note lives in SEAMS/CHANGELOG (disjoint
from T1's USAGE/README). If the builder prefers the note in USAGE, sequence after T1.
**Acceptance (R3, R4):** the static-Bearer-vs-OAuth expectation is stated once; CHANGELOG updated.
**Tag:** `autonomous`.

---

## Layer 1 — Gate

### T3 — Gate + no-runtime-change proof
**Owns:** (no new files; runs the gate)
**Depends on:** T1, T2.
**Acceptance (R2, R5):**
- `bundle exec rake` green (docs-only, so nothing should break).
- The recipe's tool name/route match the shipped code (`example_read_only`, `mcp#handle`).
- `git diff --stat` shows no change under `lib/` for this spec (docs/CHANGELOG only).

**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0006)
T1 ┐
T2 ┼─→ T3
```

T1/T2 own disjoint files (USAGE+README vs SEAMS+CHANGELOG); T3 gates.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- Token setup, seed, scope, and bearer resolution live in host-app setup docs + curl, not gem
  runtime.
- Handshake shown as pasteable curl: `initialize` → `tools/list` → `tools/call example_read_only`.
- Client-auth reality stated once (static Bearer works via curl/inspector; hosted connectors
  expect OAuth); no promise of a specific client.
- No gem runtime change.

No open decisions remain — every task is `autonomous`.
