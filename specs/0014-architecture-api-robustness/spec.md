# SPEC — architecture & API robustness

> **Build order: 5 of 6.** Recommended sequence: 0015 → 0010 → 0011 → 0013 → 0014 → 0012. Depends on: 0011. GitHub does not enforce spec order — see the release tracking issue.

Build contract for spec 0014: harden the tool/args seam so its guarantees stop resting on
private `mcp` internals and undocumented invariants, close a data-losing gap in the raw
`input_schema` escape hatch, make an ungated raw tool a visible exception, tidy the error
hierarchy layout, and collapse a duplicated helper. This is a **cold handoff**: a fresh agent
with only this folder plus the repo must be able to build it. Builds on shipped specs 0001–0013
(archived). Given/When/Then acceptance criteria; `DECIDED` marks settled choices.

In force: ADR-0001 (delegate the protocol to `mcp`), ADR-0004 (zero gem-side policy),
ADR-0007 (no auto-discovery), ADR-0012 (neutral conduit), ADR-0013 (app-owned tool list).

---

## Background

The args allow-list (spec 0001) hinges on distinguishing "the app set a raw `input_schema`"
from "the app used only `arg`/nothing". The `mcp` gem's public surface cannot express that, so
`lib/rails_mcp/args.rb` reads `mcp`'s private `@input_schema_value` ivar (args.rb:96–97). The
gem pins `mcp "~> 1.1"` (rails_mcp.gemspec:41), which permits any 1.x minor — a rename of that
ivar in mcp 1.2+ would silently flip `explicitly_set_input_schema?` with no failing test
(ARCH-01).

Worse, when a tool uses that sanctioned raw-schema escape hatch, it declares zero
`arg_definitions`, so `declared_arguments` drops **every** incoming argument and `perform` is
called with no keywords — the advertised schema says `q` is required, the client sends it, mcp
validates it present, and the pipeline throws it away before `perform` (ARCH-02).

Adjacent robustness issues ride along: a raw `MCP::Tool` listed in `RegisteredTools` silently
bypasses `authorize`+audit with no signal (API-01); the memoized class-level schema relies on
an unstated class-definition-time-only invariant (ARCH-05); the exception hierarchy is split
across the requires-only entry file and `tool.rb`, violating the layout rule (ARCH-04); and
`text_response` exists twice — a class method and an instance method that only delegates to it
(API-02 / SIMP-01).

None of the gem's guarantees change: fail-closed `authorize`, the args allow-list, undeclared-
arg dropping, one audit event per call, per-request identity, read/write neutrality, and zero
gem-side policy all stay exactly as they are. This spec makes those guarantees rest on
rails_mcp's own state and on tests, not on `mcp` internals or unwritten assumptions.

---

## Scope

### In this spec

- Own the explicit-schema bit in rails_mcp's own state instead of reading `mcp`'s private
  `@input_schema_value` ivar; add a contract/drift test that fails when `mcp` changes the
  behavior relied on (ARCH-01).
- Derive the args allow-list from the tool's **effective** input schema so a raw-schema tool
  round-trips its declared properties to `perform`; add an invocation test (ARCH-02).
- Ship a lightweight opt-in guard/test that makes a raw `MCP::Tool` (or a `call` override) in
  the tool list a deliberate, visible exception; stamp a warning comment in the template
  (API-01).
- Document the class-definition-time-only invariant behind the `@built_input_schema` memo
  (ARCH-05).
- Consolidate `RailsMcp::Error` and `RailsMcp::NotAuthorized` into `lib/rails_mcp/errors.rb`,
  required first; remove the inline `Error` from the entry file and `NotAuthorized` from
  `tool.rb` (ARCH-04).
- Collapse the duplicated `text_response` to a single public entry point (API-02 / SIMP-01).

### Out of scope

- Any behavior change to the invoke pipeline (`authorize → perform → notify`), the args/
  annotations DSL semantics, identity on `server_context`, the fail-closed seams, or read/write
  neutrality. This spec is robustness/refactor only — no guarantee changes.
- Editing `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev` skill.
  Several findings carry a `standards_amendment`; those are **tracked in spec 0015**, which owns
  all standards amendments. Do not apply them here.
- Adding an upper version bound to the `mcp` pin is optional and not required by this spec; the
  drift test (R1) is the required guardrail, per ARCH-01's own note that `~>` is not a
  substitute for a contract test.

**DECIDED (ARCH-01)** rails_mcp owns the explicit-schema bit. The `input_schema` setter override
sets `@explicit_input_schema = true` on the tool class; `explicitly_set_input_schema?` reads
that flag. No code path reads `mcp`'s `@input_schema_value` ivar.

**DECIDED (ARCH-02)** the args allow-list is the tool's **effective** schema's property keys:
when an explicit schema is set, the allow-list is that schema's `properties` keys (as symbols);
otherwise it is `declared_arg_names`. A raw-schema tool receives its declared properties in
`perform`.

**DECIDED (API-01)** the guard is opt-in and app-side: a `RegisteredTools`-shaped assertion
helper (a documented test) that flags any entry which is not a `RailsMcp::Tool` subclass, or
which overrides `call`, unless it is in an explicit allow-list — plus a warning comment stamped
into `registered_tools.rb.tt`. The gem neither warns at runtime nor blocks (ADR-0004,
ADR-0007 unchanged); the guard makes a raw tool a *visible, deliberate* exception, not a
forbidden one.

**DECIDED (ARCH-04)** error classes live in `lib/rails_mcp/errors.rb`, required first from
`lib/rails_mcp.rb`.

**DECIDED (API-02 / SIMP-01)** the instance `text_response` is the single public entry point;
the class-level twin is removed. The instance method builds the `MCP::Tool::Response` directly.

---

## Requirements

### R1 — Own the explicit-schema flag; drop the private-ivar read; pin it with a drift test (ARCH-01)

Changes: `lib/rails_mcp/args.rb`, a new/expanded test in `test/rails_mcp/args_test.rb` (or a new
`test/rails_mcp/mcp_contract_test.rb`).

- **Given** `lib/rails_mcp/args.rb`, **when** searched, **then** no method reads or writes
  `mcp`'s `@input_schema_value` ivar via `instance_variable_get`/`instance_variable_set`
  (`grep -n "@input_schema_value" lib/` returns nothing).
- **Given** a `RailsMcp::Tool` subclass that calls the `input_schema(properties:, required:)`
  setter, **when** `explicitly_set_input_schema?` is evaluated, **then** it returns `true`
  because the setter override recorded `@explicit_input_schema = true` on the class; **given** a
  subclass that used only `arg` (or neither), **then** it returns `false`.
- **Given** a bare `MCP::Tool` (no explicit schema), **when** the drift test inspects it, **then**
  it asserts the `mcp` behavior rails_mcp relies on — a bare `MCP::Tool` advertises an *empty*
  input schema (its public `input_schema_value.to_h[:properties]` is empty), and a tool that
  raw-set a schema advertises those properties — so the test **fails** if a future `bundle update
  mcp` changes that contract. The test does not reference the private ivar.
- **Given** the existing args behavior, **when** the suite runs, **then** an `arg`-only tool
  still advertises its `arg`-built schema and an explicit-schema tool still wins over `arg`
  (no behavior change; the flag is an internal substitution for the ivar read).

### R2 — Raw `input_schema` round-trips its declared properties to `perform` (ARCH-02)

Changes: `lib/rails_mcp/args.rb` (allow-list derivation), a new invocation test in
`test/rails_mcp/tool_test.rb` (or `test/rails_mcp/args_test.rb`).

- **Given** a `RailsMcp::Tool` that sets `input_schema(properties: {q: {type: "string"}},
  required: ["q"])` and no `arg`, **when** it is invoked end to end with `q: "hello"`, **then**
  `perform` receives `q: "hello"` (not `{}`). This is the exact reproduction from ARCH-02 and
  must now pass.
- **Given** that same raw-schema tool, **when** invoked with an *undeclared* argument `z: 1`
  alongside `q: "hello"`, **then** `perform` receives `q: "hello"` and **not** `z` — the
  allow-list is the effective schema's property keys, so undeclared args are still dropped
  (arg-dropping guarantee intact).
- **Given** `declared_arguments` / the allow-list source, **when** read, **then** the allow-list
  is `explicitly_set_input_schema? ? input_schema.to_h[:properties].keys.map(&:to_sym) :
  declared_arg_names` (or an equivalent that yields the effective schema's property symbols).
- **Given** an `arg`-only tool, **when** invoked, **then** its behavior is unchanged (declared
  args reach `perform`, undeclared dropped).

### R3 — Raw `MCP::Tool` in the list is a visible, deliberate exception (API-01)

Changes: `lib/generators/rails_mcp/install/templates/registered_tools.rb.tt` (stamp a warning
comment), a new stamped guard test
`lib/generators/rails_mcp/install/templates/registered_tools_guard_test.rb.tt` **or** an addition
to the existing stamped example tests, and the generator +
`test/generators/install_generator_test.rb` to stamp/assert it.

- **Given** `rails g rails_mcp:install`, **when** it runs, **then** `registered_tools.rb`
  carries a comment stating that only `RailsMcp::Tool` subclasses that do not override `call`
  carry the `authorize`/audit/allow-list guarantees, and that a bare `MCP::Tool` or a `call`
  override runs **unaudited and ungated** — a deliberate exception the app owns.
- **Given** the stamped app, **when** its guard test runs, **then** it iterates
  `RegisteredTools.all` and **fails** if any entry is not a `RailsMcp::Tool` subclass, or
  overrides `call`, unless that entry is listed in an explicit in-test `ALLOWLISTED_RAW_TOOLS`
  (empty by default) — so adding a raw tool forces the app author to add it to that list, making
  the exception visible in a diff.
- **Given** the default stamped list (only `ExampleReadOnlyTool`), **when** the guard test runs,
  **then** it passes (the example is a gated `RailsMcp::Tool`).
- **Given** the gem's runtime, **when** a raw tool is registered, **then** the gem still neither
  warns nor blocks at request time — the guarantee non-change is preserved; the guard is a test,
  not a runtime gate (ADR-0004/ADR-0007 unchanged).
- Note: the `standards_amendment` for API-01 is **tracked in spec 0015**; do not edit
  `docs/conventions.md` here.

### R4 — Document the class-definition-time-only memo invariant (ARCH-05)

Changes: `lib/rails_mcp/args.rb` (comment/`@api` note only).

- **Given** `lib/rails_mcp/args.rb`, **when** read, **then** a comment near `built_input_schema`
  (or on `arg`/`input_schema`/the annotations `read_only!` note) states that the class-level DSL
  calls (`arg`, `read_only!`, `input_schema`) run at class-definition/boot time only, that they
  are the only writers of the memoized `@built_input_schema` / `@arg_definitions` state, and that
  the memo's safety relies on those writes completing before any concurrent request-time read.
- **Given** this task, **when** done, **then** no behavior changed — this is a documentation-only
  requirement (no new frozen object, no new method), and the suite is still green.
- Note: the `standards_amendment` for ARCH-05 is **tracked in spec 0015**.

### R5 — Consolidate the error hierarchy into `lib/rails_mcp/errors.rb`, required first (ARCH-04)

Changes: new `lib/rails_mcp/errors.rb`; `lib/rails_mcp.rb` (require it first, remove the inline
`Error`); `lib/rails_mcp/tool.rb` (remove the inline `NotAuthorized`).

- **Given** `lib/rails_mcp/errors.rb`, **when** read, **then** it defines `RailsMcp::Error <
  StandardError` and `RailsMcp::NotAuthorized < Error` together, with the doc comment for
  `NotAuthorized` (the fail-closed-authorize rationale) carried over from `tool.rb`.
- **Given** `lib/rails_mcp.rb`, **when** read, **then** it `require_relative "rails_mcp/errors"`
  **before** any other submodule require (right after the version require), and it no longer
  defines `class Error < StandardError; end` inline — the entry file holds requires only.
- **Given** `lib/rails_mcp/tool.rb`, **when** read, **then** it no longer defines
  `class NotAuthorized < Error; end`; it references `NotAuthorized` (the default `authorize`
  still raises it) resolved from `errors.rb`.
- **Given** `require "rails_mcp"`, **when** loaded, **then** it loads cleanly and both
  `RailsMcp::Error` and `RailsMcp::NotAuthorized` resolve; **given** an unimplemented
  `authorize`, **when** called, **then** it still raises `RailsMcp::NotAuthorized` (fail-closed
  unchanged).
- Note: the `standards_amendment` for ARCH-04 is **tracked in spec 0015**.

### R6 — Collapse the duplicated `text_response` to one public entry point (API-02 / SIMP-01)

Changes: `lib/rails_mcp/tool.rb` (remove the class method, inline into the instance method);
existing `test/rails_mcp/tool_test.rb` assertion kept.

- **Given** `lib/rails_mcp/tool.rb`, **when** searched, **then** there is exactly one
  `text_response` definition — the instance method — and no `def self.text_response`.
- **Given** the instance method, **when** read, **then** it builds the response directly:
  `MCP::Tool::Response.new([{type: "text", text: text}])` (no delegation to a class method).
- **Given** `text_response("ok")` called on a tool instance, **when** evaluated, **then** it
  yields a single text content item equal to `"ok"` (`[{type: "text", text: "ok"}]`) — the
  existing `tool_test.rb` assertion still passes.
- **Given** `grep` of `test/`, templates, and the fixture app, **when** run, **then** no caller
  of the removed class-level `text_response` remains (the audit confirmed the only caller was the
  instance delegation; `opt_out_seams_test.rb` builds `MCP::Tool::Response` directly and is
  unaffected).

### R7 — Gate: full suite green, guarantees intact, no regressions

Changes: none of its own — this is the closing verification task.

- **Given** the repo, **when** `bundle exec rake` (minitest + standardrb) runs, **then** it is
  green.
- **Given** `grep -rn "@input_schema_value" lib/`, **when** run, **then** it returns nothing
  (R1 landed).
- **Given** the invoke pipeline, args allow-list, undeclared-arg dropping, one-event audit,
  per-request identity, fail-closed `authorize`, and read/write neutrality, **when** the suite
  exercises them, **then** all behave exactly as before this spec — the ARCH-02 fix *adds*
  round-tripping for raw-schema tools and changes nothing for `arg`-only tools.
- **Given** this spec's ownership boundary, **when** the diff is reviewed, **then** it does not
  touch `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev` skill.

---

## Non-goals (guardrails)

- No change to any gem guarantee — fail-closed, allow-list, arg-dropping, one-event, per-request
  identity, read/write neutrality, zero gem-side policy all stay. This spec is robustness and
  layout only.
- No runtime warning or block on a raw `MCP::Tool` (ADR-0004/ADR-0007 hold); the guard is a
  test.
- No standards-doc edits: every `standards_amendment` on these findings is consolidated in spec
  0015. Do not touch `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the skill.
- No upper `mcp` version bound is required (optional); the R1 drift test is the guardrail.
- No auto-discovery; the tool list stays explicit (ADR-0007).
