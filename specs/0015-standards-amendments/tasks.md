# TASKS — Standards & conventions amendments

Task breakdown for spec 0015. Each task owns a DISJOINT document, so T1–T4 are independent and
parallel; T5 (gate) depends on all four. References like `R1` point to this spec's `spec.md`.
Every task is `autonomous`.

This spec is documentation-only: it consolidates every finding's `standards_amendment` into the
four docs it OWNS. No `lib/`, test, template, ADR, README, USAGE, SEAMS, generators, or gemspec
edits — specs 0010–0014 own those. Amendments are additive or replace only the named sentence;
never delete an existing correct rule. Any rule naming a check ("grep-enforced", "CI check") is
phrased as a requirement on the code specs and cross-refs SEC-04 — this spec asserts no check
already runs.

---

## Layer 0 — Amend each standards document (parallel, disjoint files)

### T1 — `docs/conventions.md` amendments
**Owns:** `docs/conventions.md` (ONLY).
**Applies:** R1 (STD-01 versioning & deprecation + scope "never a silent break" to >=1.0),
R2 (STD-02 event-name scoped to lib/, template literal exempt), R3 (PKG-02 Keep a Changelog +
version↔changelog check), R4 (PKG-01 allowlist packaging section, PKG-04 required metadata,
PKG-03 description-matches-README, PKG-07 sig/ types), R5 (CI-01 CI matrix), R6 (SEC-03
production-default config, TEST-02 verbatim example tool, DOC-01 executable handshakes), R7
(ARCH-01 no private mcp reach, ARCH-02 effective-schema allow-list, API-01 raw-tool guard,
ARCH-05 class-definition-time state), R8 (ARCH-03 event-contract scope, DOC-04 client error
surface), R9 (ARCH-04 errors.rb layout), R10 (SEC-01 generated-example security), R11 (TEST-01
isolation, TEST-04/SIMP-07 filenames, SIMP-03/SIMP-06 one-harness + adr_constraints_test,
SIMP-04/SIMP-05 no doc-prose / instrumentation ownership).
**Structure:** replace the line-4 "semver assumed known" sentence with a Versioning & deprecation
section (R1, R3); amend the existing Naming (R2), Architecture invariants (R7, R9), Public API
discipline (R1, R8), Tests (R11), Integration reality (R6) sections in place; add new "Packaging
(public gem)" (R4, R5) and "Generated example security" (R10) sections.
**Acceptance:** every finding id above is addressed by a concrete, checkable rule in the doc;
`grep -n "assumed known" docs/conventions.md` no longer matches the semver sentence; the doc names
`errors.rb`, `RegisteredTools`, `rubygems_mfa_required`, and `bug_tracker_uri`. No other file
changed.
**Depends on:** shipped 0009–0014 model (docs only). Independent of T2/T3/T4.
**Tag:** `autonomous`.

### T2 — `REVIEW.md` amendments
**Owns:** `REVIEW.md` (ONLY).
**Applies:** R12 (SEC-02 operationalize the error-leak invariant; SEC-05 enumerate dynamic-dispatch
forms `constantize`/`const_get`/`public_send`/non-literal `send`/`__send__`; TEST-03 second
hand-mirrored integration test is a finding; TEST-05 doc-prose assertions + posture-named files are
findings; TEST-06 credential-leak tested on the real HTTP path, tautological scrub test flagged).
**Structure:** amend the "No secret or stack leak" and "No arbitrary-Ruby/console path" bullets in
the Highest-severity invariants section (SEC-02, SEC-05); add the four test rules to the Tests
section (TEST-03, TEST-05, TEST-06).
**Acceptance:** REVIEW.md's arbitrary-Ruby bullet lists `constantize`, `const_get`, `public_send`,
and non-literal `send`/`__send__`; the Tests section flags doc-prose assertions, posture-named
files, a second hand-mirrored integration harness, and a scrub test whose input never held the
secret at the level asserted. No other file changed.
**Depends on:** shipped. Independent of T1/T3/T4.
**Tag:** `autonomous`.

### T3 — `CLAUDE.md` amendments
**Owns:** `CLAUDE.md` (ONLY).
**Applies:** R13 (SEC-04 machine-checkable only if a named CI check runs it, hook != CI, extract
shared checks to a rake task; SEC-05 mirror the enumerated dynamic-dispatch forms; DOC-02
ADR-integrity clause + removed-symbol grep test; DOC-03 pre-publish SECURITY.md + linked COC,
excluded from the gem).
**Structure:** amend the "Machine-checkable ADR constraints" section (SEC-04, SEC-05); add an
ADR-integrity clause near the ADR-immutability text under "Recording decisions and learnings"
(DOC-02); add a pre-publish checklist item (DOC-03).
**Acceptance:** CLAUDE.md states a rule is machine-checkable only if a named CI check runs it and
that a local hook is not CI; lists the enumerated dynamic-dispatch forms; contains an ADR-integrity
clause requiring re-status + bidirectional link + a removed-symbol grep test; contains a pre-publish
`SECURITY.md`/`CODE_OF_CONDUCT` checklist item. No other file changed.
**Depends on:** shipped. Independent of T1/T2/T4.
**Tag:** `autonomous`.

### T4 — spec-driven-dev skill `references/testing.md` amendments
**Owns:** `.claude/skills/spec-driven-dev/references/testing.md` (ONLY).
**Applies:** R14 (STD-04 replace the stale registry references at lines 36/66 with the
`RegisteredTools.all` allow-list model + reload-safe mandatory test; remove "the registry refuses
an unregistered tool"), R15 (STD-03 posture-name ban + one-seam-per-file in "Where a test lives";
TEST-05 doc-prose ban mirrored).
**Structure:** rewrite the "Real, sociable by default" line (36) and the "Mandatory
security/fail-closed tests" registry line (66); add the file/class naming + one-seam rules to
"Where a test lives"; add the doc-prose rule.
**Acceptance:** `grep -n -i registry .claude/skills/spec-driven-dev/references/testing.md` returns
nothing referring to `RailsMcp::Registry` as a live object; the mandatory-tests list names
"`MCP::Server` refuses a `tools/call` for an unlisted name", "a redefined tool class rebuilds the
server without `ToolNotUnique`", and "no arbitrary-Ruby/console surface"; the doc bans posture-named
files and doc-prose assertions. No other file changed.
**Depends on:** shipped. Independent of T1/T2/T3.
**Tag:** `autonomous`.

---

## Layer 1 — Gate

### T5 — Coverage gate + full suite
**Owns:** no source files (verification only).
**Depends on:** T1, T2, T3, T4.
**Acceptance:**
- `bundle exec rake` (minitest + standardrb) is green — this spec changes no code, so the suite
  must be unchanged and passing.
- Every finding id with a non-empty `standards_amendment` in `tmp/all_findings.json` is addressed
  by at least one rule across the four docs (checklist below all present):
  - conventions.md: PKG-01, TEST-01, SEC-01, SEC-03, DOC-01, ARCH-01, ARCH-02, ARCH-03, TEST-02,
    TEST-04, PKG-02, CI-01, STD-01, PKG-03, PKG-04, PKG-07, DOC-04, API-01, ARCH-04, STD-02,
    ARCH-05, SIMP-03, SIMP-04, SIMP-05, SIMP-06, SIMP-07.
  - REVIEW.md: SEC-02, SEC-05, TEST-03, TEST-05, TEST-06.
  - CLAUDE.md: SEC-04, SEC-05 (mirror), DOC-02, DOC-03.
  - testing.md: STD-03, STD-04, TEST-05 (mirror).
- Only the four owned docs were modified: `git status --porcelain` lists only
  `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, and
  `.claude/skills/spec-driven-dev/references/testing.md`.
- No rule in any doc asserts a check already runs; each check-naming rule cross-refs SEC-04 as a
  code-spec requirement.
**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped)
T1 (conventions.md) ┐
T2 (REVIEW.md)      ┤
T3 (CLAUDE.md)      ┼─→ T5 (gate)
T4 (testing.md)     ┘
```

T1–T4 parallel (disjoint files); T5 gates.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- One task per owned document; the four docs are disjoint, so T1–T4 run in parallel.
- Amendments are additive or replace only the specific named sentence; no existing correct rule is
  deleted.
- This spec writes rules only. Any rule that names an enforcing check is a requirement on the code
  specs and cross-refs SEC-04; no doc here claims a check already runs.
- Where an amendment says "mirror in X and Y" (SEC-05 → REVIEW + CLAUDE; TEST-05 → REVIEW +
  testing.md; STD-03 → testing.md + REVIEW), both docs get the matching text.
- No `lib/`, test, template, ADR, README, USAGE, SEAMS, generators, or gemspec edits — specs
  0010–0014 own the code/tests/docs those findings name.

No open decisions remain — every task is `autonomous`.
