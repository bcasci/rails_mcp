# SPEC — Docs accuracy & correctness

> **Build order: 6 of 6.** Recommended sequence: 0015 → 0010 → 0011 → 0013 → 0014 → 0012. Depends on: 0011 (docs describe the corrected code/tests). GitHub does not enforce spec order — see the release tracking issue.

Build contract for spec 0012: correct four documentation claims and one audit-contract claim that
the shipped code contradicts, and pin each corrected claim with a test against the verbatim
fixture. Builds on shipped specs 0001–0011 (archived). Given/When/Then acceptance criteria;
`DECIDED` marks settled choices.

In force: ADR-0002 (HTTP-only, stateless transport), ADR-0004 (gem ships zero policy), ADR-0012
(neutral conduit), ADR-0013 (app-owned tool list). This spec changes docs, ADR statuses, one code
comment, and tests only — no runtime behavior changes.

---

## Background

Five findings from the audit report a mismatch between what the docs/comments claim and what the
shipped `mcp` gem + generated templates actually do:

- **DOC-01** — README and USAGE teach a stateless-transport handshake ("send `initialize` first",
  expect a `"Server not initialized"` error) that the shipped `stateless: true` controller can
  never produce. The string `"Server not initialized"` does not exist anywhere in `mcp-1.1.0`, and
  the transport gates every session check on `!@stateless`, so a lone `tools/call` is self-contained.
- **DOC-02** — ADR-0007 and ADR-0008 are still `Accepted` but their normative decision text and
  code samples describe the removed `RailsMcp::Registry` / `expose!` / `RailsMcp.registry.tools`
  (deleted in spec 0009 / ADR-0013). CLAUDE.md says an Accepted ADR is superseded only by a new ADR
  that links both ways.
- **ARCH-03** — `tool.rb`, `SEAMS.md`, and `USAGE.md` claim "exactly one `invoke.rails_mcp` event
  per call". A `tools/call` rejected by `mcp` at schema validation (missing/wrong-typed required
  arg) returns before the tool pipeline, so it fires **zero** events. The claim overstates the
  audit-completeness contract.
- **DOC-04** — The client-facing failure surface (what the AI client receives on a denial, an
  internal raise, and a schema rejection) is undocumented, and the raise wording is backwards:
  `mcp` wraps any raise as `"Internal error calling tool <name>: <message>"`, not a fidelity-preserving
  "tool error".
- **DOC-05** — The README/USAGE curl happy-path posts `arguments:{subject:"first call"}` expecting
  `"Looked up: first call"`, but no test asserts that exact body/result against real code.

Each fix is a doc/comment correction plus a test that runs the exact documented request against the
verbatim fixture, so a documented claim and the shipped code can never silently diverge again.

---

## Scope

### In this spec

- Delete the false stateless handshake instructions from `README.md` and `docs/USAGE.md`; state the
  stateless first-call reality; pin it with an integration test (DOC-01).
- Re-status ADR-0007 and ADR-0008 as partially superseded by ADR-0013 with bidirectional links, and
  correct the ADR-0008 decision code sample; add a grep test that no Accepted, non-superseded ADR
  names a removed symbol (DOC-02).
- Correct the "exactly one event per call" claim in `lib/rails_mcp/tool.rb`, `docs/SEAMS.md`, and
  `docs/USAGE.md` to scope it to calls that reach the pipeline; add a test that a schema-rejected
  `tools/call` fires no event (ARCH-03).
- Add a "What the client receives" subsection to `docs/SEAMS.md` and correct the raise wording in
  `docs/USAGE.md`; pin the deny / raise / schema-reject responses with a test (DOC-04).
- Add a test asserting the exact README/USAGE curl body (`arguments:{subject:"first call"}`) returns
  `"Looked up: first call"` (DOC-05).

### Out of scope

- **Standards amendments.** DOC-01, DOC-02, ARCH-03, and DOC-04 each carry a `standards_amendment`
  (to `docs/conventions.md` and `CLAUDE.md`). This spec does **not** edit `docs/conventions.md`,
  `CLAUDE.md`, `REVIEW.md`, or the `spec-driven-dev` skill — **standards amendments tracked in spec
  0015**, which consolidates all of them.
- **Rewriting the fixture's `ExampleReadOnlyTool` to load from `example_read_only_tool.rb.tt`
  verbatim** (the required-`subject`/echo divergence noted in DOC-05) is finding TEST-02, owned by
  another spec (0011). This spec asserts the documented curl body/result; whichever fixture tool the
  suite runs must return `"Looked up: first call"` for `subject:"first call"`. If the fixture tool at
  build time still returns the constant `"Looked up: example"` and ignores `subject`, the R5 test
  MUST drive the request through the verbatim `example_read_only_tool.rb.tt`-defined tool (the
  template, byte-identical) rather than adding a stubbed stand-in — no diverging harness.
- Any change to the invoke pipeline, the args/annotations DSL, the controller public-`mcp` pattern,
  identity on `server_context`, the fail-closed seams, read/write neutrality, or the `mcp` gem's
  error/handshake behavior. This spec documents what already ships; it changes no runtime code.

**DECIDED** every corrected claim is pinned by a test that runs the exact documented request against
the verbatim integration fixture (`test/integration/fixture_app/`) — never a simplified or stubbed
stand-in (mirrors spec 0005 R6 / spec 0009 R7).

**DECIDED** ADR bodies are immutable; ADR-0007/0008 change only their `Status` line plus a
bidirectional-link line, except the one factually-wrong ADR-0008 decision code sample
(`RailsMcp.registry.tools` → `RegisteredTools.all`), corrected in place because it names an API that
no longer exists (DOC-02 resolution).

**DECIDED** the corrected audit contract wording is: "exactly one `invoke.rails_mcp` event per
invocation that reaches the tool pipeline; a `tools/call` the `mcp` gem rejects at schema validation
(missing/wrong-typed required arg) or as an unknown tool, before dispatch, emits no event."

---

## Requirements

### R1 — Remove the false stateless handshake; state the reality; test it (DOC-01)

- **Given** `README.md`, **when** read, **then** the line
  `# If this returns a "not initialized" error, send an `initialize` request first (see USAGE §2a).`
  (README.md:93, under the `tools/call` curl block) is **gone**, and no `README.md` text tells the
  reader to send `initialize` before a `tools/call` or to expect a `"not initialized"` /
  `"Server not initialized"` error.
- **Given** `docs/USAGE.md`, **when** read, **then** the "handshake is ordered: send `initialize`
  **first**" paragraph and the `"Server not initialized"` note (USAGE.md ~286) are **gone**, replaced
  by a statement that with `stateless: true` (the shipped controller, `mcp_controller.rb.tt`) each
  POST is independent and self-contained, so a lone `tools/call` succeeds and `initialize` is
  **optional**. The real `Accept: application/json, text/event-stream` header note is **kept**.
- **Given** the docs, **when** searched, **then** `grep -rn "Server not initialized\|not initialized"
  README.md docs/` returns nothing.
- **Given** the verbatim stateless fixture, **when** an integration test POSTs a `tools/call` with **no
  prior `initialize`**, **then** it returns HTTP 200 with a tool result (not an error), proving the
  documented stateless first-call.

### R2 — Re-status ADR-0007 and ADR-0008; correct the ADR-0008 code; grep-test removed symbols (DOC-02)

- **Given** `docs/adr/0007-convenience-without-lock-in.md`, **when** read, **then** its `Status` line
  is `Status: Accepted (2026-08-13); partially superseded by [ADR-0013](0013-drop-registry-for-app-owned-tool-list.md) (2026-08-19)`
  (registry/`expose!`/per-endpoint-`Registry` exposure decision superseded), and its body is otherwise
  unchanged.
- **Given** `docs/adr/0008-controller-uses-mcp-public-pattern.md`, **when** read, **then** its `Status`
  line is re-statused the same way (partially superseded by ADR-0013 with a link), and the decision
  code sample `tools: RailsMcp.registry.tools` reads `tools: RegisteredTools.all`, and the prose
  "the gem's only runtime touch inside the request path is `RailsMcp.registry.tools`" is corrected to
  "…is the app-owned `RegisteredTools.all`". The rest of the body is unchanged.
- **Given** `docs/adr/0013-drop-registry-for-app-owned-tool-list.md`, **when** read, **then** it links
  back to ADR-0007 and ADR-0008 as ADRs it partially supersedes (bidirectional link, per CLAUDE.md).
- **Given** every `docs/adr/*.md`, **when** an ADR-integrity test scans them, **then** it asserts no
  ADR whose `Status` is `Accepted` and NOT marked superseded/partially-superseded names any removed
  symbol — `RailsMcp::Registry`, `RailsMcp.registry`, `expose!`, or `ToolNameCollision` — **except an
  ADR that itself performs a supersession** (its body contains a `Supersedes:` line), which
  necessarily names the symbol it removed. Exempt: `_template.md`, superseded/partially-superseded
  ADRs (0007/0008/0009), and the removing ADR **0013** (it has a `Supersedes:` line). A future
  Accepted ADR that reintroduces a live registry reference fails. These are the same symbols
  `test/rails_mcp/opt_out_seams_test.rb` proves gone.
- **Given** the ADR-integrity test with ADR-0013 present and `Accepted`, **when** run, **then** it is
  GREEN — the `Supersedes:`-line exemption covers 0013 (the ADR that removed the registry), so the
  exemption is exercised, not merely asserted, and the test does not false-positive on the removal ADR.

### R3 — Correct the "exactly one event per call" claim; test the schema-reject boundary (ARCH-03)

- **Given** `lib/rails_mcp/tool.rb`, **when** read, **then** the class comment (tool.rb ~23-24) no
  longer says the gem emits "exactly one `invoke.rails_mcp` audit event per call whether it succeeds,
  is denied, or raises"; it says exactly one event per invocation **that reaches the tool pipeline**,
  and notes that a `tools/call` the `mcp` gem rejects upstream (schema validation of a missing/
  wrong-typed required arg, or an unknown tool) emits **no** event. This is a comment change only; no
  code path changes.
- **Given** `docs/SEAMS.md` (SEAMS.md ~95-96, "publishes **exactly one** … event per tool
  invocation") and `docs/USAGE.md` (USAGE.md ~158, "publishes exactly one `invoke.rails_mcp` event
  per call"), **when** read, **then** both are scoped to invocations that reach the pipeline and both
  name the pre-pipeline schema-rejection / unknown-tool short-circuit as emitting no event, pointing at
  `mcp`'s own `around_request`/`exception_reporter` seams for auditing rejected calls if the app needs
  it.
- **Given** the verbatim fixture, **when** an integration test POSTs a `tools/call` for a real tool
  with a **missing required argument** (schema-rejected by `mcp` before dispatch), **then** it asserts
  that **no** `invoke.rails_mcp` event fires (subscribe to `RailsMcp::Instrumentation::EVENT`, assert
  the count is zero) while the response is an `mcp`-level error — pinning the audit boundary.

### R4 — Document the client-facing error/denial surface; correct the raise wording; test it (DOC-04)

- **Given** `docs/SEAMS.md`, **when** read, **then** a "What the client receives" subsection lists the
  three failure responses on the wire: (a) **schema rejection** — an `mcp`-level error returned before
  the pipeline runs, so **no** audit event fires; (b) **`authorize`/`perform` raise** — `mcp` wraps it
  as `"Internal error calling tool <name>: <message>"`, the app's `exception_reporter` receives the
  exception detail, and the one `invoke.rails_mcp` event's `error:` payload carries the exception;
  (c) **success** — the `text_response` content shape.
- **Given** `docs/USAGE.md` (USAGE.md ~410, "If `perform` raises, the error is surfaced as a tool
  error"), **when** read, **then** the wording no longer promises message fidelity; it states that a
  raise surfaces to the client as `mcp`'s `"Internal error calling tool <name>: …"` wrapper and that
  the audit event records the exception.
- **Given** the verbatim fixture, **when** an integration test drives (a) a denial (`authorize`
  raising `RailsMcp::NotAuthorized`), (b) a `perform` raise, and (c) a schema rejection, **then** it
  asserts each documented wire response: the raise response body contains `"Internal error calling
  tool "`, the denial surfaces as the documented error while its one audit event still fires, and the
  schema rejection returns an `mcp`-level error with no event — matching the new SEAMS.md subsection.

### R5 — Pin the taught curl happy-path (DOC-05)

- **Given** the exact README/USAGE curl body
  `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"example_read_only","arguments":{"subject":"first call"}}}`,
  **when** an integration test POSTs it against the verbatim fixture controller, **then** the result
  content text is `"Looked up: first call"` (`isError: false`), asserting the documented happy-path
  against real code.
- **Given** the fixture tool that returns the required-`subject` echo, **when** the R5 test runs,
  **then** it drives the tool defined by the verbatim `example_read_only_tool.rb.tt` template (required
  `arg :subject`, `perform(subject:)` echoing `"Looked up: #{subject}"`) — never a stubbed stand-in.
  (If the fixture's default `ExampleReadOnlyTool` at build time still ignores `subject` and returns the
  constant `"Looked up: example"` — the TEST-02 divergence owned by spec 0011 — this test loads the
  template tool verbatim rather than depending on TEST-02 landing first.)

---

## Non-goals (guardrails)

- No standards-doc edits: `docs/conventions.md`, `CLAUDE.md`, `REVIEW.md`, and the `spec-driven-dev`
  skill are untouched here — all standards amendments (DOC-01, DOC-02, ARCH-03, DOC-04) are
  consolidated in spec 0015.
- No runtime behavior change. R1–R5 correct docs, ADR statuses, one code comment, and one factually
  wrong ADR code sample, and add tests. The invoke pipeline, DSL, controller pattern, identity,
  fail-closed seams, allow-list, arg-dropping, one-event guarantee, per-request identity, and
  read/write neutrality are all unchanged.
- No rewrite of an accepted ADR body beyond the status line, the bidirectional-link line, and the
  single wrong ADR-0008 code/prose reference (R2).
- No new fixture harness; every pinning test runs the verbatim fixture (spec 0005 R6 / 0009 R7).
- The DOC-05 fixture-tool-from-template convergence (TEST-02) is spec 0011's; this spec does not edit
  the fixture's tool definition beyond what R5 needs to drive the documented body.
