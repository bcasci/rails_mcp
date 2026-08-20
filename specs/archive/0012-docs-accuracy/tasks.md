# TASKS — Docs accuracy & correctness

Completed Thu Aug 20 00:52:11 EDT 2026 at commit dec6d48

Task breakdown for spec 0012. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0011 (archived). References like `R1` point to this spec's `spec.md`. All findings resolved:
DOC-01, DOC-02, ARCH-03, DOC-04, DOC-05.

Doc/ADR/comment edits (T1–T4) own disjoint files and are parallel. The pinning tests (T5) and the
ADR-integrity grep test (T2 owns it, disjoint) close the loop. T6 is the gate, depends on all.

Every task is `autonomous`.

---

## Layer 0 — Correct docs, ADR statuses, and the code comment (parallel, disjoint files)

### T1 — README: drop the false handshake note; keep curl bodies intact — DONE
**Owns:**
- `README.md` (CHANGED: delete the `# If this returns a "not initialized" error, send an
  `initialize` request first …` line at README.md:93; no README text tells the reader to send
  `initialize` first or to expect a `"not initialized"` error. The `tools/call` curl body and its
  `arguments:{subject:"first call"}` / `Looked up: first call` expected output are **kept
  verbatim** — T5 pins them.)

**Depends on:** shipped 0001–0011.
**Acceptance (R1, DOC-05):** `grep -n "not initialized" README.md` returns nothing; the
`tools/call` curl block still posts `arguments:{"subject":"first call"}` and comments the
`Looked up: first call` result.
**Tag:** `autonomous`.

### T2 — ADRs: re-status 0007/0008, correct the 0008 code, link 0013 back; add the ADR-integrity grep test — DONE
**Owns:**
- `docs/adr/0007-convenience-without-lock-in.md` (CHANGED: `Status:` →
  `Accepted (2026-08-13); partially superseded by [ADR-0013](0013-drop-registry-for-app-owned-tool-list.md) (2026-08-19)`;
  body otherwise unchanged)
- `docs/adr/0008-controller-uses-mcp-public-pattern.md` (CHANGED: same `Status:` re-status; in the
  Decision code sample `tools: RailsMcp.registry.tools` → `tools: RegisteredTools.all`; the prose
  "the gem's only runtime touch inside the request path is `RailsMcp.registry.tools`" →
  "…is the app-owned `RegisteredTools.all`"; rest of body unchanged)
- `docs/adr/0013-drop-registry-for-app-owned-tool-list.md` (CHANGED: add a line noting it partially
  supersedes ADR-0007 and ADR-0008, with links — bidirectional per CLAUDE.md; existing body
  otherwise unchanged)
- `test/rails_mcp/adr_integrity_test.rb` (NEW: scans every `docs/adr/*.md`; for each ADR whose
  `Status` line contains `Accepted` and does NOT contain `superseded` (case-insensitive) **and whose
  body does NOT contain a `Supersedes:` line**, asserts its body names none of `RailsMcp::Registry`,
  `RailsMcp.registry`, `expose!`, `ToolNameCollision` — the removed symbols
  `test/rails_mcp/opt_out_seams_test.rb` proves gone. Exempt: `_template.md`, superseded/partially-
  superseded ADRs (0007/0008/0009), and any ADR with a `Supersedes:` line — including ADR-0013, which
  removed those symbols and must name them. The test must be GREEN with ADR-0013 present and Accepted.)

**Depends on:** shipped 0001–0011. Independent of T1/T3/T4 (disjoint files).
**Acceptance (R2, DOC-02):** ADR-0007/0008 re-statused with links; ADR-0008 code reads
`RegisteredTools.all`; ADR-0013 links back; the grep test is green and would fail if any Accepted,
non-superseded ADR reintroduced a removed symbol.
**Tag:** `autonomous`.

### T3 — tool.rb comment: scope the one-event claim to the pipeline — DONE
**Owns:**
- `lib/rails_mcp/tool.rb` (CHANGED: the class comment ~line 23-24 — "emitting exactly one
  `invoke.rails_mcp` audit event per call whether it succeeds, is denied, or raises (R4)" → "exactly
  one `invoke.rails_mcp` audit event per invocation **that reaches the tool pipeline** (success,
  denial, or raise); a `tools/call` the `mcp` gem rejects upstream — schema validation of a
  missing/wrong-typed required arg, or an unknown tool — emits no event." Comment only; no code
  changes to `authorize`/`perform`/`call`/the pipeline.)

**Depends on:** shipped. Independent of T1/T2/T4 (disjoint files).
**Acceptance (R3, ARCH-03):** the comment scopes the one-event guarantee to the pipeline entry and
names the pre-pipeline short-circuit; `git diff` shows only comment lines changed.
**Tag:** `autonomous`.

### T4 — USAGE + SEAMS: stateless reality, scoped audit contract, client-facing error surface — DONE
**Owns:**
- `docs/USAGE.md` (CHANGED:
  - R1: delete the "handshake is ordered: send `initialize` **first**" paragraph and the
    `"Server not initialized"` note (~line 286); state that with `stateless: true` each POST is
    independent so a lone `tools/call` succeeds and `initialize` is optional; keep the
    `Accept: application/json, text/event-stream` note.
  - R3: scope the "publishes exactly one `invoke.rails_mcp` event per call" claim (~line 158) to
    invocations that reach the pipeline; name the schema-rejection / unknown-tool short-circuit as
    emitting no event and point at `mcp`'s `around_request`/`exception_reporter`.
  - R4: correct "If `perform` raises, the error is surfaced as a tool error" (~line 410) — a raise
    surfaces to the client as `mcp`'s `"Internal error calling tool <name>: …"` wrapper; the audit
    event records the exception.)
- `docs/SEAMS.md` (CHANGED:
  - R3: scope the "publishes **exactly one** … event per tool invocation" claim (~line 95) to the
    pipeline entry and name the pre-pipeline rejection as emitting no event.
  - R4: add a "What the client receives" subsection listing (a) schema rejection → `mcp`-level error
    before the pipeline, no event; (b) `authorize`/`perform` raise → `"Internal error calling tool
    <name>: <message>"` wrapper, `exception_reporter` gets detail, the one audit event's `error:`
    carries the exception; (c) success → the `text_response` content shape.)

**Depends on:** shipped. Independent of T1/T2/T3 (disjoint files).
**Acceptance (R1, R3, R4; DOC-01, ARCH-03, DOC-04):** no `"Server not initialized"`/"not
initialized" in USAGE; the ordered-handshake paragraph gone; the one-event claim scoped in both
files; the raise wording corrected; the SEAMS "What the client receives" subsection present.
**Tag:** `autonomous`.

---

## Layer 1 — Pin every corrected claim with a verbatim-fixture test

### T5 — Integration tests pinning DOC-01 / ARCH-03 / DOC-04 / DOC-05 against the verbatim fixture — DONE
**Owns:**
- `test/integration/docs_accuracy_test.rb` (NEW: all four pinning tests, driven through the verbatim
  fixture controller — never a stubbed stand-in):
  1. **DOC-01 / R1** — POST a `tools/call` with **no prior `initialize`** against the stateless
     fixture; assert HTTP 200 with a tool result (not an error).
  2. **ARCH-03 / R3** — subscribe to `RailsMcp::Instrumentation::EVENT`; POST a `tools/call` for a
     real tool with a **missing required argument**; assert **zero** events fired and the response is
     an `mcp`-level error.
  3. **DOC-04 / R4** — drive (a) a denial (`authorize` raising `RailsMcp::NotAuthorized`) — assert
     the documented error response AND that its one audit event still fired; (b) a `perform` raise —
     assert the response body contains `"Internal error calling tool "`; (c) a schema rejection —
     assert an `mcp`-level error with no event.
  4. **DOC-05 / R5** — POST the exact README/USAGE curl body
     (`params:{name:"example_read_only", arguments:{subject:"first call"}}`); assert the result
     content text is `"Looked up: first call"` (`isError: false`). Drive the tool defined by the
     verbatim `example_read_only_tool.rb.tt` (required `arg :subject`, echoing `subject`); do NOT
     depend on the TEST-02 fixture convergence landing first.

**Depends on:** T1, T2, T3, T4 (tests assert the corrected docs' behavior; the fixture is shipped).
**Acceptance (R1, R3, R4, R5):** all four tests green against the verbatim fixture; each drives the
exact documented request; no stubbed stand-in.
**Tag:** `autonomous`.

---

## Layer 2 — Gate

### T6 — Full gate + spec checks — DONE
**Owns:** (no new files — runs checks only)

**Depends on:** T1, T2, T3, T4, T5.
**Acceptance (all R):**
- `bundle exec rake` (minitest + standardrb) is green.
- `grep -rn "Server not initialized" README.md docs/` returns nothing (R1).
- `grep -rn "not initialized" README.md docs/USAGE.md` returns nothing (R1).
- `test/rails_mcp/adr_integrity_test.rb` passes; ADR-0007/0008 `Status` lines contain
  `partially superseded by [ADR-0013]`; ADR-0008 no longer contains `RailsMcp.registry.tools`;
  ADR-0013 links to 0007 and 0008 (R2).
- `git diff lib/rails_mcp/tool.rb` shows only comment-line changes (R3).
- `docs/conventions.md`, `CLAUDE.md`, `REVIEW.md`, and the `spec-driven-dev` skill are unchanged by
  this spec (standards amendments belong to spec 0015).
**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0011)
T1 ┐
T2 ┤
T3 ┼─→ T5 ─→ T6
T4 ┘
```

T1–T4 parallel (disjoint files); T5 pins the corrected docs; T6 gates.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- Every corrected claim is pinned by a test running the exact documented request against the
  verbatim integration fixture — never a stubbed stand-in.
- ADR bodies are immutable except: ADR-0007/0008 status lines + bidirectional-link lines, and the one
  factually-wrong ADR-0008 code/prose reference (`RailsMcp.registry.tools` → `RegisteredTools.all`),
  which names a removed API.
- The corrected audit contract: exactly one `invoke.rails_mcp` event per invocation that reaches the
  pipeline; a call `mcp` rejects at schema validation or as an unknown tool, before dispatch, emits
  no event.
- No runtime behavior change; this spec edits docs, ADR statuses, one code comment, one wrong ADR code
  sample, and tests only.
- Standards amendments (DOC-01, DOC-02, ARCH-03, DOC-04) are NOT applied here — spec 0015 consolidates
  them. This spec does not edit `docs/conventions.md`, `CLAUDE.md`, `REVIEW.md`, or the
  `spec-driven-dev` skill.
- The DOC-05 fixture-tool-from-template convergence (TEST-02) is spec 0011's; T5 drives the verbatim
  template tool for its curl assertion rather than waiting on it.

No open decisions remain — every task is `autonomous`.
