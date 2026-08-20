# TASKS — test suite overhaul (correctness, conventions, simplification)

Completed Thu Aug 20 00:02:23 EDT 2026 at commit c810449

Task breakdown for spec 0011. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0009 (archived). References like `R1` point to this spec's `spec.md`.

Scope reminder: tests + the integration fixture + install `.tt` templates ONLY. This spec MUST NOT
edit `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev` skill — every
finding's `standards_amendment` is tracked in **spec 0015**.

The integration file `test/integration/real_world_hardening_test.rb` is heavily touched (R1, R2,
R3, R4) and then renamed (R7). To keep tasks on DISJOINT files, **T1 owns that file for its whole
lifetime** — including its content edits (autoload fix, verbatim example calls, migrated identity
proof, bearer-leak proof) and its final rename to `mcp_request_flow_test.rb`. The fixture
(`fixture_app/boot.rb`) is co-owned by T1 (it is the same integration flow). No other task edits
either file.

---

## Layer 0 — Independent test edits (parallel, disjoint files)

### T1 — Integration flow: autoload, verbatim example, identity proof, bearer-leak, rename — DONE
**Owns:**
- `test/integration/real_world_hardening_test.rb` → renamed to
  `test/integration/mcp_request_flow_test.rb` (class `RealWorldHardeningTest` → `McpRequestFlowTest`)
- `test/integration/fixture_app/boot.rb`
- `test/integration/controller_end_to_end_test.rb` (DELETE)

**Does:**
- **R1:** `require "mcp"` at top and reference `MCP::Server` in `setup`/fixture load so
  `MCP::ToolNotUnique` autoloads deterministically; the ToolNotUnique test passes in isolation.
- **R2:** load `ExampleReadOnlyTool` VERBATIM from `example_read_only_tool.rb.tt` (drop the
  `Object.const_set`/`perform(**)` stand-in); add a byte-for-byte guard test; supply required
  `:subject` in every example `tools/call`; assert the README/USAGE curl body
  `{subject: "first call"}` returns `"Looked up: first call"`.
- **R3:** DELETE `controller_end_to_end_test.rb`; migrate only
  `test_interleaved_requests_do_not_bleed_identity` (Queue/barrier) onto the fixture controller via
  `post_mcp`; drop any stale `RailsMcp.serve` comment.
- **R4:** add a `tools/call` carrying `Authorization: Bearer <sentinel>` and assert the token
  appears in neither the audit payload (including nested `:args`) nor the HTTP body; add a proof
  that a raising authorize/perform surfaces a generic error, not the raw message.
- **R7:** rename the file + class (pure rename after the merges above).

**Depends on:** shipped 0001–0009.
**Acceptance (R1, R2, R3, R4, R7):** the renamed file and its ToolNotUnique test pass alone;
example tool is verbatim + guarded + driven with `:subject`; the identity proof runs on the
verbatim controller; bearer never leaks; `controller_end_to_end_test.rb` is gone.
**Tag:** `autonomous`.

### T2 — Unit-test de-duplication (tool_test, annotations_test) — DONE
**Owns:**
- `test/rails_mcp/tool_test.rb`
- `test/rails_mcp/annotations_test.rb`

**Does:**
- **R5:** delete the success-count, perform-raise-count, and payload-content assertions from
  `tool_test.rb`; keep authorize-before-perform, undeclared-arg drop, user-from-`server_context`,
  and `test_authorize_denial_emits_exactly_one_event_with_error`; add the ownership-split comment.
- **R6:** delete `test_read_only_only_still_emits_read_only_hint` (byte-identical duplicate);
  keep the four distinct annotation tests.

**Depends on:** shipped. Independent of T1/T3 (disjoint files).
**Acceptance (R5, R6):** no duplicated instrumentation contract in `tool_test.rb`; one
`readOnlyHint: true` test in `annotations_test.rb`; both files green.
**Tag:** `autonomous`.

### T3 — Doc-prose deletion + drift guard into generator suite — DONE
**Owns:**
- `test/docs/getting_started_docs_test.rb` (DELETE)
- `test/docs/neutral_conduit_docs_test.rb` (DELETE)
- `test/rails_mcp/getting_started_docs_test.rb` (DELETE)
- `test/generators/install_generator_test.rb` (CHANGED: absorb the two doc-vs-template drift
  guards as template-content assertions)

**Does:**
- **R8:** delete all three doc-prose suites (including the "send initialize first" handshake
  assertion); move ONLY the two doc-snippet-equals-template drift guards into
  `install_generator_test.rb` as `.tt`-vs-doc-snippet checks; confirm `skip_forgery_protection` /
  `hosts.grep(String)` coverage remains in the generator suite.

**Depends on:** shipped. Independent of T1/T2 (disjoint files).
**Acceptance (R8):** no doc-prose presence assertions anywhere; the two drift guards live in the
generator suite; no runtime coverage dropped.
**Tag:** `autonomous`.

---

## Layer 1 — Relocation into new/shared files (depends on Layer 0 for tool_test)

### T4 — Relocate opt_out_seams; single adr_constraints_test; drop subsumed check — DONE
**Owns:**
- `test/rails_mcp/opt_out_seams_test.rb` (DELETE)
- `test/adr_constraints_test.rb` (NEW)
- `test/test_rails_mcp.rb` (CHANGED: remove the jsonrpc/transport grep, now in adr_constraints)
- `test/rails_mcp/tool_test.rb` (CHANGED: absorb the two behavioral seams)

**Does:**
- **R9:** move the raw-`MCP::Tool`-unaudited and plain-`tools:`-array-is-allow-list behavioral
  seams into `tool_test.rb` as `RailsMcp::Tool`-boundary tests; consolidate the ADR
  source-grep/symbol-absence guards + the moved jsonrpc/transport grep into
  `test/adr_constraints_test.rb`; drop `test_registry_file_is_deleted` (subsumed).

**Depends on:** T2 (both edit `tool_test.rb`; T4 runs after T2 to avoid a write conflict).
**Acceptance (R9):** `opt_out_seams_test.rb` gone; every `test/rails_mcp/<x>_test.rb` maps 1:1 to
`lib/rails_mcp/<x>.rb`; all constraint grep guards in one file; allow-list + no-gem-registry
coverage preserved.
**Tag:** `autonomous`.

---

## Layer 2 — CI isolation + gate

### T5 — Per-file isolation CI step + full gate — DONE
**Owns:**
- `.github/workflows/*.yml` (the existing test workflow — add a per-file isolation step)

**Does:**
- **R1 (CI half):** add a step that runs each `test/**/*_test.rb` alone (loop `ruby -Itest <file>`)
  and fails if any file fails in isolation.
- **R10:** run `bundle exec rake` (minitest + standardrb) to green; run the per-file loop locally
  to confirm every file passes alone; confirm no `lib/` file was edited by this spec and each of
  the six guarantees still has a witness.

**Depends on:** T1, T2, T3, T4.
**Acceptance (R1, R10):**
- `bundle exec rake` green.
- Every `test/**/*_test.rb` passes in isolation (CI step + local run).
- `git diff --name-only` for this spec shows no path under `lib/` and no edit to
  `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the `spec-driven-dev` skill.
**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0009)
T1 ┐
T2 ┼──────────┐
T3 ┘          │
   T2 ──→ T4 ─┤
              └─→ T5 (gate)
T1, T3 ───────────→ T5
```

- T1, T2, T3 are parallel (disjoint files).
- T4 depends on T2 (both edit `tool_test.rb`).
- T5 gates on all of T1–T4.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- The example template `example_read_only_tool.rb.tt` is correct; TEST-02 is a fixture defect. The
  fixture loads the template verbatim and every call supplies `:subject`. No `.tt` template is
  edited unless strictly required (it is not).
- Canonical integration file is `test/integration/mcp_request_flow_test.rb` (class
  `McpRequestFlowTest`); `controller_end_to_end_test.rb` is deleted, its identity proof migrated.
- The three doc-prose suites are deleted; only the two doc-vs-template drift guards survive, moved
  into `install_generator_test.rb`.
- ADR source-grep constraint guards live in one `test/adr_constraints_test.rb`; the existing
  no-jsonrpc/transport grep moves there from `test_rails_mcp.rb`.
- `instrumentation_test.rb` owns the payload/event-count contract; `tool_test.rb` keeps only
  Tool-specific wiring.
- The integration file and fixture are owned solely by T1 across all their edits + the rename, to
  keep task file-sets disjoint.
- No standards-doc edits: every `standards_amendment` on these findings is tracked in **spec 0015**.

No open decisions remain — every task is `autonomous`.
