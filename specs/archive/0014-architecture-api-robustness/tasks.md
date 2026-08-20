# TASKS — architecture & API robustness

Completed Thu Aug 20 00:34:39 EDT 2026 at commit 91bff8e

Status: all tasks DONE (T1–T5 delivered and gated).

Task breakdown for spec 0014. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0013 (archived). References like `R1` point to this spec's `spec.md`. Every task is
`autonomous`.

Ownership note: this spec fixes code/tests/docs-templates only. It must **not** edit
`docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev` skill — spec 0015 owns
all standards amendments.

---

## Layer 0 — independent, disjoint-file changes (parallel)

### T1 — Own the explicit-schema flag + effective-schema allow-list + memo invariant note — DONE
**Owns:**
- `lib/rails_mcp/args.rb` (CHANGED):
  - `input_schema` setter override sets `@explicit_input_schema = true` on the class (R1).
  - `explicitly_set_input_schema?` reads `@explicit_input_schema` — **no** `instance_variable_get`
    of `mcp`'s `@input_schema_value` (R1).
  - the args allow-list is derived from the **effective** schema:
    `explicitly_set_input_schema? ? input_schema.to_h[:properties].keys.map(&:to_sym) :
    declared_arg_names` (R2). `declared_arguments` filters against that effective allow-list.
  - a comment near `built_input_schema` states the class-definition-time-only invariant: `arg`,
    `read_only!`, `input_schema` run at boot only; they are the only writers of the memoized
    `@built_input_schema`/`@arg_definitions`; memo safety relies on writes completing before any
    concurrent request-time read (R4).
- `test/rails_mcp/args_test.rb` (CHANGED): assert `explicitly_set_input_schema?` is `true` after
  the raw setter and `false` for arg-only/none; assert the effective allow-list = the raw
  schema's property keys; assert an `arg`-only tool still advertises its `arg`-built schema and
  an explicit schema still wins over `arg` (R1, R2).
- `test/rails_mcp/mcp_contract_test.rb` (NEW): the drift test — a bare `MCP::Tool` advertises an
  empty schema via the **public** `input_schema_value.to_h`, a raw-set schema advertises its
  properties; fails on a `bundle update mcp` that changes the contract; references no private
  ivar (R1).

**Depends on:** shipped 0001–0013.
**Acceptance (R1, R2, R4):** `grep -n "@input_schema_value" lib/` is empty; a raw-schema tool's
allow-list is its schema properties; the drift test asserts the public mcp contract; the memo
invariant is documented. No behavior change for `arg`-only tools.
**Tag:** `autonomous`.

### T2 — Consolidate the error hierarchy into `errors.rb` — DONE
**Owns:**
- `lib/rails_mcp/errors.rb` (NEW): `RailsMcp::Error < StandardError` and
  `RailsMcp::NotAuthorized < Error`, with the `NotAuthorized` doc comment carried from `tool.rb`
  (R5).
- `lib/rails_mcp.rb` (CHANGED): `require_relative "rails_mcp/errors"` first (right after the
  version require, before other submodules); remove the inline `class Error < StandardError; end`
  (R5).
- `lib/rails_mcp/tool.rb` (CHANGED): remove `class NotAuthorized < Error; end`; the default
  `authorize` still raises `NotAuthorized` (now resolved from `errors.rb`). **This file's
  `text_response` change is owned by T3, not here** — T2 touches only the `NotAuthorized`
  definition and its require path.
- `test/rails_mcp/errors_test.rb` (NEW, optional but preferred): assert `require "rails_mcp"`
  loads clean and both `RailsMcp::Error` and `RailsMcp::NotAuthorized` resolve, and that an
  unimplemented `authorize` raises `RailsMcp::NotAuthorized` (R5).

**Depends on:** shipped 0001–0013.
**Acceptance (R5):** `errors.rb` defines both classes; entry file requires it first and holds no
inline `Error`; `tool.rb` no longer defines `NotAuthorized`; gem loads clean; fail-closed
`authorize` still raises `NotAuthorized`.
**Tag:** `autonomous`.
**Disjointness:** T2 and T3 both touch `lib/rails_mcp/tool.rb`. T2 edits only the
`NotAuthorized` class definition (top of the module) and requires; T3 edits only the
`text_response` methods. They must land sequentially (see graph) to avoid a merge on that file.

### T4 — Registered-tools guard: stamp warning + guard test; generator + generator test — DONE
**Owns:**
- `lib/generators/rails_mcp/install/templates/registered_tools.rb.tt` (CHANGED): add a comment
  block stating that only `RailsMcp::Tool` subclasses not overriding `call` carry
  authorize/audit/allow-list, and that a bare `MCP::Tool` or a `call` override runs
  unaudited/ungated — a deliberate, app-owned exception (R3).
- `lib/generators/rails_mcp/install/templates/registered_tools_guard_test.rb.tt` (NEW): iterates
  `RegisteredTools.all`, fails on any entry that is not a `RailsMcp::Tool` subclass or that
  overrides `call`, unless in an in-test `ALLOWLISTED_RAW_TOOLS` (empty default). Passes for the
  default list (`ExampleReadOnlyTool`) (R3).
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED): stamp the guard test
  template.
- `test/generators/install_generator_test.rb` (CHANGED): assert the warning comment is stamped
  into `registered_tools.rb` and that the guard test file is stamped and its default form passes
  (R3).

**Depends on:** shipped 0001–0013. Independent of T1/T2/T3 (disjoint files).
**Acceptance (R3):** generator stamps the warning comment + guard test; the guard fails for a
non-`RailsMcp::Tool` / `call`-override entry not on the allow-list and passes for the default
list; the gem still neither warns nor blocks at runtime (guard is a test).
**Tag:** `autonomous`.

---

## Layer 1 — depends on T2 (same file)

### T3 — Collapse `text_response` to the single instance method — DONE
**Owns:**
- `lib/rails_mcp/tool.rb` (CHANGED): remove `def self.text_response(text)`; the instance
  `text_response` builds the response directly:
  `MCP::Tool::Response.new([{type: "text", text: text}])` (R6). Only the `text_response` methods
  change; the `NotAuthorized` change from T2 stays.
- `test/rails_mcp/tool_test.rb` (CHANGED): keep/adjust the existing assertion that
  `text_response("ok")` yields `[{type: "text", text: "ok"}]`; drop any assertion on the
  class-level form; add an invocation test proving a raw `input_schema` tool receives its
  declared property in `perform` (R2, R6). If T1 placed the R2 invocation test in
  `args_test.rb`, this file need only own the `text_response` assertions — do not duplicate.

**Depends on:** T2 (both edit `lib/rails_mcp/tool.rb`).
**Acceptance (R6):** exactly one `text_response` (instance); builds the Response directly; the
existing content-shape assertion passes; no remaining caller of the class form.
**Tag:** `autonomous`.

---

## Layer 2 — gate

### T5 — Full gate + guarantee-intact verification — DONE
**Owns:**
- no source files of its own; runs the gate and the spec's own checks (R7).

**Depends on:** T1, T2, T3, T4.
**Acceptance (R7):**
- `bundle exec rake` (minitest + standardrb) is green.
- `grep -rn "@input_schema_value" lib/` returns nothing.
- The invoke pipeline, args allow-list, undeclared-arg dropping, one-event audit, per-request
  identity, fail-closed `authorize`, and read/write neutrality behave exactly as before (the
  ARCH-02 fix only *adds* round-tripping for raw-schema tools).
- The diff touches none of `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the
  `spec-driven-dev` skill.
**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0013)
T1 ┐
T2 ─→ T3 ┐
T4 ┘      │
          ├─→ T5
T1 ───────┤
T4 ───────┘
```

T1 and T4 are fully independent (disjoint files). T2 → T3 are serialized because both edit
`lib/rails_mcp/tool.rb`. T5 gates on all of T1–T4.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- rails_mcp owns the explicit-schema bit (`@explicit_input_schema`); no read of `mcp`'s private
  `@input_schema_value`. A public-contract drift test pins the mcp behavior relied on (ARCH-01).
- The args allow-list is the tool's **effective** schema's property keys; a raw-schema tool
  round-trips its declared properties to `perform`; undeclared args are still dropped (ARCH-02).
- The raw-tool guard is opt-in and app-side (a stamped guard test + a warning comment); the gem
  neither warns nor blocks at runtime (ADR-0004/ADR-0007 unchanged) (API-01).
- The `@built_input_schema` memo invariant (class-definition-time-only writers) is documented in
  a comment (ARCH-05).
- Error classes live in `lib/rails_mcp/errors.rb`, required first; entry file holds requires
  only; `NotAuthorized` leaves `tool.rb` (ARCH-04).
- One public `text_response` — the instance method, building the Response directly (API-02 /
  SIMP-01).
- Ownership boundary: no edits to `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the
  `spec-driven-dev` skill. All standards amendments for ARCH-01/02/04/05 and API-01 are tracked
  in **spec 0015**.

No open decisions remain — every task is `autonomous`.
