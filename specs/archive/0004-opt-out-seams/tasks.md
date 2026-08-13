# TASKS — opt-out seams for tool creation and exposing

**Completed Thu Aug 13 10:52:19 EDT 2026 at commit 9aab57d** — all tasks delivered and audited.

Task breakdown for spec 0004. Same constraint: **each task owns a DISJOINT set of files**.
Builds on shipped specs 0001–0003 (archived): the `arg`/annotations DSL, `RailsMcp::Tool`,
`RailsMcp::Registry`, and the install generator.

Every task is `autonomous` — decisions are locked in spec.md / ADR-0007. `R1` points to this
spec's `spec.md`. Tasks own disjoint files and can build in parallel after their deps.

---

## Layer 0 — DSL yields to explicit values

### T0 — `input_schema` / `annotations` yield to an explicitly-set value — DONE
**Owns:**
- `lib/rails_mcp/args.rb` (CHANGED: `input_schema` returns an explicitly-set schema when the
  tool set one via the `mcp` macro; builds from `arg` definitions only when no explicit schema
  is set)
- `lib/rails_mcp/annotations.rb` (CHANGED if the mixin shadows the `mcp` `annotations` macro —
  same yield-to-explicit fix; per R2 BUILD-TIME CHECK)
- `test/rails_mcp/args_test.rb` (CHANGED: raw `input_schema` wins; `arg`-only still builds; both
  → explicit wins)
- `test/rails_mcp/annotations_test.rb` (CHANGED: raw `annotations` wins; `read_only!`-only still
  emits `readOnlyHint`)

**Depends on:** shipped 0001.
**Acceptance (R1, R2):**
- A raw `input_schema` on a `RailsMcp::Tool` is the advertised schema; `arg`-only unchanged;
  explicit wins when both present.
- A raw `annotations(...)` is emitted; `read_only!`-only unchanged.

**Tag:** `autonomous` — yield-to-explicit DECIDED (R1/R2, ADR-0007).

---

## Layer 1 — Co-located registration

### T1 — `expose!` macro — DONE
**Owns:**
- `lib/rails_mcp/tool.rb` (CHANGED: add the class-level `expose!` macro — registers `self` on
  `RailsMcp.registry`; idempotent via the registry)
- `test/rails_mcp/expose_test.rb` (NEW: `expose!` self-registers; idempotent; a
  defined-but-unexposed subclass is absent — R5)

**Depends on:** shipped 0001 (registry). Independent of T0 (disjoint files).
**Acceptance (R3, R5):**
- `expose!` puts the tool on `RailsMcp.registry` with no initializer entry; idempotent.
- A `RailsMcp::Tool` subclass never `register`ed/`expose!`d is absent from the registry (no
  auto-discovery).

**Tag:** `autonomous` — `expose!` co-located, generator default stays central (R3, ADR-0007).

---

## Layer 2 — Documented escapes + guardrail proof

### T2 — Registry-escape tests + opt-out docs — DONE
**Owns:**
- `test/rails_mcp/opt_out_seams_test.rb` (NEW: a raw `MCP::Tool` registers via ordinary
  `register` and runs, listable, with NO `authorize`/`invoke.rails_mcp` event and NO gem
  warning/error; a per-endpoint `RailsMcp::Registry.new` serves only its own tools; a plain
  `tools:` array to `MCP::Server` works without `RailsMcp.registry`; no `inherited`-hook
  auto-registration exists — R4, R5)
- `docs/USAGE.md` (CHANGED: an "opting out" section — raw `input_schema`/`annotations`,
  `expose!`, raw `MCP::Tool` (unaudited, the app's choice), per-endpoint registry, plain array,
  and `mcp`'s own `around_request`/`exception_reporter` for observability)
- `docs/SEAMS.md` (CHANGED: note the pipeline is an opinionated default; a raw `MCP::Tool` sits
  outside it by design)

**Depends on:** T0 (raw schema), T1 (`expose!`) — so docs and tests reflect them.
**Acceptance (R4, R5):**
- Raw `MCP::Tool` registration runs unaudited with no gem warning; per-endpoint registry and
  plain array both work; no auto-discovery path exists.
- Docs show every opt-out as a supported seam, document-only, no nannying.

**Tag:** `autonomous` — escapes are existing behavior; this proves and documents them (ADR-0007).

---

## Dependency graph (build order)

```
(shipped 0001-0003)
T0 ┐
   ├─→ T2
T1 ┘
```

T0 (DSL yield) and T1 (`expose!`) are independent (disjoint files), parallel after the shipped
base. T2 (docs + escape tests) waits on both.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0007 — do not relitigate):**

- `input_schema` / `annotations` yield to an explicitly-set value; DSL builds only when used.
- `expose!` added as an optional co-located macro; generator default stays central.
- Raw `MCP::Tool` registers via ordinary `register`, unaudited, document-only — no warning, no
  block, no `unaudited:` flag, no `register_raw`.
- Per-endpoint registry and plain `tools:` array are supported, tested escapes.
- No auto-discovery — exposure is always explicit.

No open decisions remain — every task is `autonomous`; the build runs unattended.
