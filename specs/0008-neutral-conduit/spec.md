# SPEC — de-opinion the gem surface (neutral MCP conduit)

Build contract for spec 0008: remove the read-only / staff / internal posture from the gem's
shipped surface so it matches what the code actually is — a neutral MCP tool-exposure conduit
(ADR-0012) — and fix the two doc bugs the install stress test found. No gem runtime behavior
change. Builds on shipped specs 0001–0007 (archived). Given/When/Then acceptance criteria.

Governing decision: **ADR-0012** (neutral conduit; supersedes ADR-0003 read-only). Unchanged:
ADR-0004 (zero policy), ADR-0005 (identity on `server_context`; its framing is clarified — the
identity is whatever the app resolves, not specifically "staff"), ADR-0008 (controller pattern),
ADR-0011 (host guard).

---

## Background

Nothing in `lib/` enforces read-only — `read_only!` only sets an advisory MCP annotation, and
the invoke pipeline runs whatever `perform` does. "Read-only v1", "act-as-staff-user", and
"internal staff-only" are **posture** in docs/templates/comments, not code. They drove repeated
scope-creep. This spec strips the posture and neutralizes the identity language, keeping the
seams and the optional `read_only!` annotation. It also fixes two doc bugs: the USAGE §1a
controller snippet that diverges from the hardened stamped template, and the missing curl
`Accept` header / `initialize` note in the recipe.

---

## Scope

### In this spec

- Remove read-only/mutation posture from `README`, `USAGE`, `SEAMS`, `conventions`, the
  `annotations.rb` comment, and the example-tool/template comments. Keep `read_only!` (optional
  advisory annotation) working.
- Neutralize "staff user" / "which human" / "internal staff-only" / "act-as-staff" language to
  "the identity your app resolves" (or "the acting user"), in templates and docs. Keep the
  `user:` keyword and the two frozen seams unchanged.
- Fix USAGE §1a: show the hardened stamped controller (with `skip_forgery_protection` and
  `allowed_hosts:`) or point at the generated file — no simplified diverging copy.
- Add the curl reality to the recipe: `Accept: application/json, text/event-stream` is required;
  if a bare `tools/call` returns "not initialized", send `initialize` first.
- Mark ADR-0003 `Status: Superseded by ADR-0012` (status-line edit only; never rewrite its body).

### Out of scope

- Any gem runtime/behavior change (annotations, invoke pipeline, seams, controller, registry) —
  none. This is docs/templates/comments only, plus the ADR-0003 status line.
- Building mutation support, approval flows, or an auth mechanism — the gem already runs write
  tools; no code needed (ADR-0012).

**DECIDED** `read_only!` stays as an optional advisory annotation; the gem does not gate writes
and ships no read-only mandate (ADR-0012).

**DECIDED** the identity keyword stays `user:` (neutral); only the surrounding "staff/internal"
prose is removed.

**DECIDED** ADR-0003's body is immutable; only its `Status` line changes to point at ADR-0012.

---

## Requirements

### R1 — No read-only / mutation posture on the shipped surface

- **Given** `lib/`, `docs/` (excluding `docs/adr/`), and `README.md`, **when** searched, **then**
  there is no posture claiming the gem is read-only or that tools may not mutate (e.g. "read-only
  v1", "no tool may mutate", "must not mutate", "v1 is read-only"). Advisory mentions of the
  `read_only!` annotation and a read-only *example* are fine; a mandate is not.
- **Given** the gem, **when** a tool's `perform` writes, **then** the gem runs it (no gate) —
  unchanged behavior, now matched by the docs.

### R2 — `read_only!` still works (advisory annotation, no regression)

- **Given** a tool that calls `read_only!`, **when** advertised, **then** it carries
  `readOnlyHint: true` (spec 0001 R5 behavior unchanged).
- **Given** a tool that does not, **when** advertised, **then** it is not marked read-only.

### R3 — Neutral identity framing

- **Given** the templates (`mcp_controller.rb.tt`, `application_mcp_tool.rb.tt`) and docs,
  **when** read, **then** the acting identity is described neutrally ("the identity your app
  resolves" / "the acting user"), not as necessarily a "staff" user or an "internal-only"
  audience. The `user:` keyword and `authorize(user:, args:, tool:)` signature are unchanged.

### R4 — USAGE §1a matches the hardened stamped controller

- **Given** `docs/USAGE.md` §1a, **when** read, **then** its controller example includes
  `skip_forgery_protection` and `allowed_hosts: Rails.application.config.hosts.grep(String)` (or
  it explicitly directs the reader to edit the generated `app/controllers/mcp_controller.rb`
  rather than copy the snippet) — no diverging simplified copy that drops the hardening.

### R5 — Curl recipe reality

- **Given** the Getting-started recipe, **when** read, **then** it states that requests send
  `Accept: application/json, text/event-stream`, and that if a bare `tools/call` returns a
  "not initialized" error the client sends `initialize` first.

### R6 — No gem runtime change; ADR-0003 superseded

- **Given** `lib/` (the `.rb` runtime, excluding template `.tt` comment text and the
  `annotations.rb` comment), **when** compared, **then** no runtime behavior changed.
- **Given** `docs/adr/0003-read-only-v1.md`, **when** read, **then** its `Status` is
  "Superseded by ADR-0012" with a link, and its Context/Decision/Consequences are unchanged.

---

## Non-goals (guardrails)

- No gem runtime/behavior change (R6).
- No new opinion added in read/write, identity, permissions, audience, tenancy, or persistence
  (ADR-0012) — this spec only *removes* posture.
- No rewrite of an accepted ADR body (only ADR-0003's status line).
