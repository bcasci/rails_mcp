# SPEC — test suite overhaul (correctness, conventions, simplification)

> **Build order: 3 of 6.** Recommended sequence: 0015 → 0010 → 0011 → 0013 → 0014 → 0012. Depends on: 0015. GitHub does not enforce spec order — see the release tracking issue.

Build contract for spec 0011: fix a set of test-suite defects surfaced by an independent audit —
order-dependent green, a false verbatim-fixture claim, a hand-mirrored integration harness, prose
tests that pin the wrong handshake, a tautological credential-scrub test, duplicate coverage, and
theme-named/duplicate-basename files. This spec touches **tests, the integration fixture, and the
install templates only**. It does not change any gem runtime behavior and keeps all six guarantees
intact (fail-closed, allow-list, arg-dropping, one-event, per-request identity, read/write
neutrality). Builds on shipped specs 0001–0009 (archived).

In force: ADR-0004 (zero gem-side policy), ADR-0005 (identity), ADR-0012 (neutral conduit),
ADR-0013 (app-owned tool list). This spec makes no architectural decision and adds no ADR.

---

## Background

The suite is green today but the audit found the green is partly luck and partly self-referential:

- `test/integration/real_world_hardening_test.rb:260` asserts on `MCP::ToolNotUnique`, a constant
  the `mcp` gem lazily autoloads; the file only passes because an *earlier* test in the full run
  first references `MCP::Server` and triggers the autoload. Run alone the file `NameError`s.
- The same integration file claims every HTTP proof runs the byte-for-byte stamped templates, but
  the fixture (`test/integration/fixture_app/boot.rb`) hand-writes `ExampleReadOnlyTool` via
  `Object.const_set` with `def perform(**)` and no required arg — diverging from the shipped
  template `example_read_only_tool.rb.tt` (which has `arg :subject, :string, required: true`).
- `test/integration/controller_end_to_end_test.rb` is a second, hand-mirrored end-to-end harness
  subclassing `ActionController::Base` — forbidden by the "test the artifact, not a copy" rule and
  redundant with the verbatim fixture, except for one unique thread-safety proof.
- Three doc-prose suites assert English/marketing sentences appear in `.md` files; one pins the
  wrong stateless handshake ("send initialize first") as a requirement.
- `test/rails_mcp/instrumentation_test.rb`'s credential-scrub test is a tautology (checks
  top-level keys the input never had; the secret sits nested under `:args`), and no test proves
  no-leak on the real HTTP path.
- `tool_test.rb` re-asserts the exactly-one-event/payload-key contract owned by
  `instrumentation_test.rb`; `annotations_test.rb` has a byte-identical duplicate test.
- Test files are named for spec themes (`*_hardening_`, `*_end_to_end_`), two share the basename
  `getting_started_docs_test.rb`, and one doc test is misfiled under `test/rails_mcp/`.

---

## Scope

### In this spec

- Force the `MCP::ToolNotUnique` autoload so the integration file passes in isolation, and add a
  CI step running each `*_test.rb` alone. (TEST-01)
- Load `ExampleReadOnlyTool` verbatim from its `.tt`, guard it byte-for-byte, and drive the taught
  required-`:subject` curl end-to-end. (TEST-02)
- Delete the hand-mirrored `controller_end_to_end_test.rb`, migrating only its interleaved-identity
  thread-safety proof onto the verbatim fixture. (TEST-03, SIMP-03)
- Prove no-credential-leak on the real HTTP path and fix the tautological scrub test. (TEST-06)
- De-duplicate `tool_test.rb` (instrumentation contract) and `annotations_test.rb` (identical
  readOnlyHint test). (TEST-07, SIMP-05, TEST-08, SIMP-02)
- Delete the three doc-prose suites, preserving only doc-vs-template drift guards by moving them
  into the generator suite. (TEST-05, SIMP-04)
- Rename theme-named integration files, consolidate the duplicate basename, relocate the misfiled
  doc test, and relocate `opt_out_seams_test.rb`'s tests to their subjects + a single
  `adr_constraints_test.rb`. (TEST-04, SIMP-06, SIMP-07)

### Out of scope

- Any change to gem runtime (`lib/`) other than nothing at all — this spec edits tests, the
  integration fixture, and the install `.tt` templates only. (The templates are edited only if
  TEST-02 reveals the example template itself is wrong; see R2 — DECIDED it is not, so the
  template is left untouched and only the fixture is fixed.)
- Editing `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev` skill. Several
  findings carry a `standards_amendment`; **all standards amendments are tracked in spec 0015** and
  must not be applied here.

---

## Ownership boundary (non-negotiable)

This spec fixes tests/fixtures/templates ONLY. It MUST NOT edit `docs/conventions.md`, `REVIEW.md`,
`CLAUDE.md`, or the `spec-driven-dev` skill (including its `references/testing.md`). Every finding's
`standards_amendment` is **tracked in spec 0015** — restate the behavior as a concrete test change
here; do not codify the rule in a standards doc.

---

## DECIDED (settled choices — do not relitigate)

- **DECIDED** the example template `example_read_only_tool.rb.tt` is correct as shipped
  (`arg :subject, :string, required: true`, `def perform(subject:)`, returns
  `"Looked up: #{subject}"`). TEST-02 is a **fixture** defect, not a template defect: the fixture
  is brought into line with the template, and every `tools/call` supplies `subject`.
- **DECIDED** the canonical integration file after this spec is
  `test/integration/mcp_request_flow_test.rb` (class `McpRequestFlowTest`), which is
  `real_world_hardening_test.rb` renamed after the merge in R3. `controller_end_to_end_test.rb` is
  deleted, not renamed.
- **DECIDED** the three doc-prose suites are deleted outright. The only residual worth keeping is
  the doc-snippet-equals-template drift guard, which moves into
  `test/generators/install_generator_test.rb` as a template-content assertion. No doc-prose test
  survives anywhere.
- **DECIDED** the ADR source-grep constraint guards live together in a new
  `test/adr_constraints_test.rb`; `test/test_rails_mcp.rb`'s existing no-jsonrpc/transport grep
  moves there too.
- **DECIDED** `instrumentation_test.rb` owns the payload-shape and event-count contract;
  `tool_test.rb` keeps only Tool-specific wiring (authorize-before-perform, undeclared-arg drop,
  user from `server_context`, and the denial-before-perform single-event wiring proof).

---

## Requirements

### R1 — Integration file passes in isolation; CI runs each file alone (TEST-01)

Files: `test/integration/real_world_hardening_test.rb` (renamed to
`test/integration/mcp_request_flow_test.rb` in R7), CI config
(`.github/workflows/*.yml` — the existing test workflow).

- **Given** the integration file, **when** it references `MCP::ToolNotUnique`, **then** the
  constant is forced to load deterministically before the assertion (e.g. `require "mcp"` at the
  top **and** referencing `MCP::Server` — which autoloads it — in the file's `setup`/fixture load),
  so the assertion no longer depends on another test having autoloaded it.
- **Given** `ruby -Itest test/integration/mcp_request_flow_test.rb -n <the ToolNotUnique test>`
  run in isolation, **when** executed, **then** it passes with no `NameError: uninitialized
  constant MCP::ToolNotUnique`.
- **Given** the CI workflow, **when** it runs, **then** it includes a step that executes each
  `test/**/*_test.rb` file individually (e.g. a loop `ruby -Itest <file>` per file), and that step
  passes — so order-dependence cannot ship.

### R2 — Example tool loaded verbatim, guarded, and the taught curl exercised (TEST-02)

Files: `test/integration/fixture_app/boot.rb`,
`test/integration/mcp_request_flow_test.rb` (formerly `real_world_hardening_test.rb`).
Reference (unchanged): `lib/generators/rails_mcp/install/templates/example_read_only_tool.rb.tt`.

- **Given** the fixture, **when** it boots, **then** `ExampleReadOnlyTool` is loaded VERBATIM from
  `example_read_only_tool.rb.tt` the same way the other three templates are loaded — no
  `Object.const_set` stand-in, no hand-written `perform(**)`.
- **Given** a byte-for-byte guard test (mirroring the existing per-template guards), **when** run,
  **then** it asserts the source loaded for `ExampleReadOnlyTool` equals the rendered
  `example_read_only_tool.rb.tt`, failing if the two diverge.
- **Given** a cookieless `tools/call` for the example tool with `arguments: {subject: "first
  call"}` (the exact body taught in `README.md` and `docs/USAGE.md` §2a), **when** posted through
  the controller, **then** the result is `"Looked up: first call"`.
- **Given** every other `tools/call` against the example tool in the file, **when** posted, **then**
  it supplies the template's required `:subject` arg (a call with `arguments: {}` would be
  schema-rejected before `perform`, which the file must not silently rely on).

### R3 — Delete the hand-mirrored controller harness; migrate the identity proof (TEST-03, SIMP-03)

Files: DELETE `test/integration/controller_end_to_end_test.rb`; CHANGE
`test/integration/mcp_request_flow_test.rb` (formerly `real_world_hardening_test.rb`).

- **Given** the test tree, **when** searched, **then** `controller_end_to_end_test.rb` no longer
  exists and no test subclasses `ActionController::Base` directly or hand-defines
  `McpController`/`RegisteredTools` as an integration stand-in.
- **Given** the interleaved-requests identity-bleed proof (formerly
  `controller_end_to_end_test.rb` `test_interleaved_requests_do_not_bleed_identity`), **when**
  migrated, **then** it runs on the verbatim fixture's controller (the byte-for-byte stamped
  `mcp_controller.rb.tt`) using the file's `post_mcp` helper, keeping its Queue/barrier
  interleaving mechanism, and asserts each concurrent request's audit payload carries only its own
  acting user (no identity bleed).
- **Given** the three proofs the deleted file shared with the fixture (fail-closed-before-auth,
  authenticated-call-attributed-in-audit, `tools/list` returns only registered), **when** the
  fixture runs, **then** those proofs remain present (they already exist in the integration file);
  none is lost.
- **Given** the migrated code, **when** read, **then** no stale comment references a removed
  `RailsMcp.serve` seam.

### R4 — No-credential-leak proven on the real HTTP path; scrub tautology fixed (TEST-06)

Files: `test/integration/mcp_request_flow_test.rb` (formerly `real_world_hardening_test.rb`),
`test/rails_mcp/instrumentation_test.rb`.

- **Given** a `tools/call` posted through the controller carrying an `Authorization: Bearer
  <token>` header (token a known unique sentinel), **when** the call completes, **then** the
  captured `invoke.rails_mcp` (a.k.a. the `RailsMcp::Instrumentation`) payload contains no
  substring of the token — including inside the nested `payload[:args]` — and the HTTP response
  body contains no substring of the token.
- **Given** a tool whose `authorize` or `perform` raises, **when** invoked through the controller,
  **then** the surfaced HTTP error is a generic message, not the raw exception message or a
  backtrace.
- **Given** `instrumentation_test.rb`'s credential test, **when** rewritten, **then** its input
  actually contains the secret at the level asserted (e.g. it drives args carrying a token and
  asserts the token does not appear anywhere in the payload including nested `:args`) — the old
  `test_payload_excludes_credentials` (which checked only top-level keys the input never had) is
  removed or corrected so it can no longer pass tautologically.

### R5 — De-duplicate the instrumentation contract in tool_test (TEST-07, SIMP-05)

Files: `test/rails_mcp/tool_test.rb`.

- **Given** `tool_test.rb`, **when** read, **then** it no longer contains the success-count
  (`test_success_emits_exactly_one_event`), perform-raise-count
  (`test_perform_raise_emits_exactly_one_event_with_error`), or payload-content
  (`test_success_event_payload_carries_user_tool_and_args`,
  `test_event_args_are_the_declared_args_only`) assertions — those belong to
  `instrumentation_test.rb`.
- **Given** `tool_test.rb`, **when** read, **then** it KEEPS Tool-specific wiring: authorize
  precedes perform, undeclared args are dropped before the payload, the user flows from
  `server_context`, and `test_authorize_denial_emits_exactly_one_event_with_error` (the
  denial-before-perform single-event wiring proof).
- **Given** a comment in `tool_test.rb`, **when** read, **then** it states the ownership split:
  the event-count/payload-shape contract is owned by `instrumentation_test.rb`; Tool tests assert
  only wiring.
- **Given** the suite, **when** run, **then** the exactly-one-event and frozen-payload-keys
  guarantees still have witnesses (in `instrumentation_test.rb` and the integration file) — no
  guarantee loses its last witness.

### R6 — Remove the byte-identical annotation test (TEST-08, SIMP-02)

Files: `test/rails_mcp/annotations_test.rb`.

- **Given** `annotations_test.rb`, **when** read, **then** it contains exactly one test asserting
  `read_only!` sets `readOnlyHint: true`; the duplicate `test_read_only_only_still_emits_read_only_hint`
  (byte-identical body to `test_read_only_sets_read_only_hint_true`) is deleted.
- **Given** the remaining tests, **when** run, **then** read/write neutrality coverage is intact:
  `read_only!` sets `readOnlyHint: true`, `read_only!` clears `destructiveHint`, an unannotated
  tool is not read-only, and a raw `annotations(...)` call is emitted unchanged — all still present.

### R7 — Rename theme/posture-named files; unique basenames; files beside their subject (TEST-04, SIMP-07)

Files: RENAME `test/integration/real_world_hardening_test.rb` →
`test/integration/mcp_request_flow_test.rb` (class `RealWorldHardeningTest` →
`McpRequestFlowTest`); handled with R8 for the doc files.

- **Given** the integration directory, **when** listed, **then** there is one integration file for
  the HTTP request flow, `mcp_request_flow_test.rb` (class `McpRequestFlowTest`), and no test
  filename encodes a spec theme or posture word (`_hardening_`, `_end_to_end_`, `real_world_`,
  `smoke_`, `sanity_`, `neutral_conduit_`).
- **Given** the whole `test/` tree, **when** basenames are compared, **then** no two test files
  share a basename.
- **Given** the rename, **when** done, **then** it is a pure rename (file + class name); no
  assertion changes and no guarantee is touched beyond the merges already specified in R1–R4.

### R8 — Delete the doc-prose suites; keep only the doc-vs-template drift guard (TEST-05, SIMP-04)

Files: DELETE `test/docs/getting_started_docs_test.rb`,
`test/docs/neutral_conduit_docs_test.rb`, `test/rails_mcp/getting_started_docs_test.rb`;
CHANGE `test/generators/install_generator_test.rb`.

- **Given** the test tree, **when** searched, **then** none of the three doc-prose suites exists,
  and no remaining test asserts that a prose/marketing sentence or a `CHANGELOG` line appears in a
  `.md` file (no regex-over-README/USAGE/SEAMS/conventions presence assertions).
- **Given** the "send initialize first" / "not initialized" prose assertion (formerly in
  `neutral_conduit_docs_test.rb`), **when** the suite runs, **then** that assertion is gone — the
  test no longer pins the stateless handshake claim in place. (Whether the doc claim itself is
  right is DOC-01's concern in another spec; this spec only removes the test that defended it.)
- **Given** the two doc-snippet-equals-template drift guards (formerly
  `neutral_conduit_docs_test.rb:103-109` and `getting_started_docs_test.rb:50-56`, which
  cross-check that a doc snippet equals the stamped template), **when** kept, **then** they are
  moved into `install_generator_test.rb` as template-content assertions comparing the rendered
  `.tt` to the doc snippet — not as prose-presence checks. No other assertion from the three
  suites is preserved.
- **Given** the load-bearing hardening content (`skip_forgery_protection`, `hosts.grep(String)`),
  **when** the suite runs, **then** it is still asserted in `install_generator_test.rb` and the
  integration file (it already is) — deleting the doc suites drops no runtime coverage.

### R9 — Relocate opt_out_seams tests; single adr_constraints_test; drop subsumed registry check (SIMP-06)

Files: DELETE `test/rails_mcp/opt_out_seams_test.rb`; CHANGE `test/rails_mcp/tool_test.rb`;
NEW `test/adr_constraints_test.rb`; CHANGE `test/test_rails_mcp.rb`.

- **Given** the two behavioral seams in `opt_out_seams_test.rb` (a raw `MCP::Tool` served on
  `MCP::Server` runs unaudited; a plain `tools:` array is the allow-list), **when** relocated,
  **then** they live in `tool_test.rb` as assertions about `RailsMcp::Tool`'s boundary (that Tool
  does not wrap a non-`RailsMcp::Tool`), and both still pass.
- **Given** the ADR source-grep/symbol-absence guards (registry/`expose!`/`ToolNameCollision`
  symbols undefined, the `lib/` grep for those symbols, no `inherited` hook) plus the existing
  no-jsonrpc/transport grep from `test/test_rails_mcp.rb`, **when** consolidated, **then** they all
  live together in one `test/adr_constraints_test.rb`, and `test/test_rails_mcp.rb` no longer
  carries the jsonrpc/transport grep.
- **Given** `test_registry_file_is_deleted` (the `registry.rb` path-absent check), **when**
  reviewed, **then** it is dropped — it is subsumed by the symbol-absence and `lib/`-grep guards
  (a resurrected `registry.rb` defining `Registry` fails those anyway).
- **Given** the result, **when** the `test/rails_mcp/` directory is inspected, **then** every
  `test/rails_mcp/<x>_test.rb` maps 1:1 to a `lib/rails_mcp/<x>.rb`, and no unit spec is named for
  a spec theme.
- **Given** the suite, **when** run, **then** allow-list and no-gem-registry coverage is preserved
  (the symbol-absence and `lib/`-grep guards are retained in `adr_constraints_test.rb`).

### R10 — Full gate green; guarantees intact (all)

Files: whole suite.

- **Given** `bundle exec rake` (minitest + standardrb), **when** run, **then** it is green.
- **Given** the per-file isolation run (R1's CI step) executed locally over `test/**/*_test.rb`,
  **when** run, **then** every file passes alone.
- **Given** the six gem guarantees (fail-closed, allow-list, arg-dropping, one-event, per-request
  identity, read/write neutrality), **when** the suite runs, **then** each still has at least one
  witness test and no gem runtime file under `lib/` was edited by this spec.

---

## Non-goals (guardrails)

- No change to any `lib/` gem runtime file. This spec edits tests, the integration fixture, and
  (only if strictly required — DECIDED it is not) install `.tt` templates.
- No standards-doc edits. Every `standards_amendment` on these findings is **tracked in spec
  0015**; do not touch `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev`
  skill here.
- No behavior change dressed as a test fix — the guarantees are asserted the same, only more
  correctly and without duplication.
- No new doc-prose test, ever; no second hand-mirrored integration harness.
