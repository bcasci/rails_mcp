# SPEC — Standards & conventions amendments

> **Build order: 1 of 6.** Recommended sequence: 0015 → 0010 → 0011 → 0013 → 0014 → 0012. Depends on: none — build first; it corrects the standards the later specs build against. GitHub does not enforce spec order — see the release tracking issue.

Build contract for spec 0015: consolidate EVERY `standards_amendment` raised in the audit into
concrete edits to the four standards documents this spec **owns**:

- `docs/conventions.md`
- `REVIEW.md`
- `CLAUDE.md`
- the `spec-driven-dev` skill's `.claude/skills/spec-driven-dev/references/testing.md`

Assigned finding ids: **STD-01, STD-02, STD-03, STD-04**. In addition, this spec is the single
owner of every other finding's `standards_amendment` field (PKG-01, TEST-01, SEC-01–SEC-05,
DOC-01–DOC-04, ARCH-01–ARCH-05, TEST-02–TEST-06, PKG-02/03/04/07, CI-01, API-01, SIMP-03–SIMP-07).
Specs 0010–0014 fix the code/tests/docs those findings name but must NOT touch these four
documents — this spec applies every prose amendment they defer.

---

## Background

The audit found that the four standards docs above are, in several places, aspirational,
self-contradictory, or stale: they assert machine enforcement that does not exist (SEC-04),
name a removed `Registry` (STD-04), state an absolute "one canonical event name" rule the gem's
own templates break (STD-02), leave a `0.x` versioning/deprecation policy invented ad hoc and
hidden behind "assumed known" (STD-01), and govern test method names but not file/class names,
letting posture-framed files ship (STD-03). Each code finding also carried a `standards_amendment`
describing the rule that, had it existed, would have caught the finding at review time.

This spec turns every one of those amendments into a checkable house rule so the autonomous
reviewer and the AI builder catch the same class of defect next time. It changes **no runtime
code** — only the four standards documents.

---

## Scope

### In this spec

- Edit `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, and
  `.claude/skills/spec-driven-dev/references/testing.md` to add/replace the rules described by
  every finding's `standards_amendment`.
- Group edits by target document (one task per document, disjoint files).
- Where an amendment says "mirror in X and Y" (SEC-05, TEST-05, STD-03), apply the matching text
  in both docs.

### Out of scope

- Any change to `lib/`, generator templates, tests, ADRs, `README.md`, `docs/USAGE.md`,
  `docs/SEAMS.md`, `docs/generators.md`, or the gemspec — those are owned by specs 0010–0014.
  This spec only writes the standards that those specs' code changes will be measured against.
- Adding or running new CI checks, rake tasks, or greps. This spec **writes the rule** that a
  check must exist (SEC-04, PKG-02, CI-01); implementing the check belongs to the code specs.
- Any behavior change to the gem's guarantees (fail-closed, allow-list, arg-dropping, one-event,
  per-request identity, read/write neutrality, zero gem-side policy). Documentation only.

**DECIDED** one task per target document; the four documents are disjoint files so all four tasks
are parallel. A final gate task runs `bundle exec rake` plus this spec's own grep checks.

**DECIDED** amendments are **additive or replacing**, never destructive of an existing correct
rule. Where a finding says "replace conventions.md:4's blanket assumed-known" (STD-01, PKG-02),
replace only the named sentence, keep the surrounding section.

**DECIDED** this spec records the rule; it does not assert a check already runs. Any rule that
names a check ("grep-enforced", "a CI check asserts…") is phrased as a **requirement on the code
specs**, and the enforcing-check finding (SEC-04) is cross-referenced, so no doc claims machine
enforcement that does not yet exist.

---

## Requirements

Each requirement names the exact file it changes, gives a concrete Given/When/Then a fresh agent
can verify by reading the resulting doc, and cites the finding id(s) it resolves.

### R1 — Versioning & deprecation policy (replaces "semver assumed known")

- **Given** `docs/conventions.md`, **when** read, **then** the blanket "semver … assumed known
  and not repeated here" sentence (currently line 4) is replaced by an explicit **Versioning &
  deprecation** section stating: pre-1.0 minor versions MAY break public seams without a
  deprecation cycle (SemVer §4 / 0.x has no compatibility guarantee); each such break is recorded
  in `CHANGELOG.md` under the new version; at 1.0 the frozen-contract rule (ship old + new, warn,
  remove one minor later) activates; the README states the current stability level. **(STD-01)**
- **Given** the same doc's Public API discipline section (currently "frozen contracts … never a
  silent break"), **when** read, **then** that "never a silent break" rule is scoped to `>= 1.0`
  so it no longer contradicts the 0.1.0→0.2.0 break. **(STD-01)**

### R2 — "One canonical event name" scoped to `lib/`; templates exempt

- **Given** `docs/conventions.md`, **when** read, **then** the "one canonical name, defined once
  in code … do not hardcode the string in multiple places" rule (currently line 18) is amended to:
  in gem code (`lib/rails_mcp/**`) the event name appears exactly once — the `EVENT` constant; all
  other gem references use the constant (grep-enforced, cross-ref SEC-04). Generated templates MAY
  use the literal string because the app subscribes before the gem constant loads; this is the
  sole exception and must be commented as intentional in the template. **(STD-02)**

### R3 — CHANGELOG follows Keep a Changelog; version↔changelog check required

- **Given** `docs/conventions.md`, **when** read, **then** the Versioning section (R1) states:
  `CHANGELOG.md` follows Keep a Changelog; when `version.rb` bumps, the matching `[Unreleased]`
  block MUST be promoted to a dated `## [X.Y.Z] - DATE` section with Added/Changed/Removed
  groupings and compare link refs in the same commit, and a `vX.Y.Z` git tag cut; a version bump
  with changes still under `[Unreleased]` is release-blocking; a CI check asserts `VERSION` has a
  matching dated section (adding that check is a code-spec task, cross-ref SEC-04). **(PKG-02)**

### R4 — Packaging (public gem) section: allowlist, metadata, types

- **Given** `docs/conventions.md`, **when** read, **then** a new **Packaging (public gem)**
  section requires: `spec.files` is an explicit allowlist of runtime paths only, never a denylist,
  framed as a security rule (shipping the control catalog — `REVIEW.md`, `.githooks/`, ADRs,
  specs, `.claude/` — leaks it), with a test asserting the built gem's file list excludes every
  internal path. **(PKG-01)**
- **Given** the same section, **when** read, **then** it lists the required gemspec metadata:
  `homepage_uri`, `source_code_uri`, `changelog_uri`, `bug_tracker_uri`, and
  `rubygems_mfa_required = 'true'`. **(PKG-04)**
- **Given** the same section, **when** read, **then** it states the gemspec summary/description is
  public API copy that MUST match the current README one-liner and must not reference removed
  concerns; when an ADR removes a capability the gemspec description is part of the change surface.
  **(PKG-03)**
- **Given** the same section, **when** read, **then** it states: ship `sig/` only if it types the
  public API and is validated in CI; a default RBS stub MUST NOT be shipped — remove it until real
  types exist; any use of a dependency's private API requires an upper version bound in the gemspec
  AND a drift test that fails when the internal name disappears. **(PKG-07, cross-ref ARCH-01)**

### R5 — CI matrix rule

- **Given** `docs/conventions.md`, **when** read, **then** the Packaging (public gem) section
  includes a **CI matrix** rule: CI MUST test the full declared support range — every minor Ruby
  from `required_ruby_version` up to current stable (including the `.tool-versions` dev Ruby) and
  the min + latest of each Rails major covered by the dependency floors; a change to
  `required_ruby_version` or a dependency floor MUST update the matrix in the same change;
  single-version CI is insufficient for a public gem. **(CI-01)**

### R6 — Integration reality: production-default config, verbatim example tool, executable handshakes

- **Given** `docs/conventions.md`'s Integration reality section, **when** read, **then** it adds:
  a stamped default that reads a Rails config value (`config.hosts`, etc.) MUST be tested with that
  value at its **production default** (empty), not a test-populated value; if the fixture must add
  the value to pass, the default is a product finding. **(SEC-03)**
- **Given** the same section, **when** read, **then** it adds: the verbatim-fixture rule covers
  EVERY stamped file the end-to-end call touches, **including the example tool**; each stamped
  file the fixture loads carries a source-equals-template guard test; a fixture tool exercised by
  an HTTP proof must be loaded from its `.tt` and guarded, and calls must supply the template's
  required args; a `const_set` stand-in for a stamped class is itself the divergence the rule
  forbids. **(TEST-02, cross-ref DOC-05)**
- **Given** the same section, **when** read, **then** it adds: any documented HTTP handshake/curl
  recipe must be backed by an integration test that runs the exact request sequence against the
  verbatim fixture; a doc step describing an error the shipped transport cannot emit (or a
  handshake it does not require) is a product finding; handshake instructions must match the
  transport ADR (0002 stateless). **(DOC-01)**

### R7 — Architecture invariants: no private `mcp` reach, effective-schema allow-list, class-definition-time state

- **Given** `docs/conventions.md`'s "Delegate the protocol" bullet, **when** read, **then** it
  adds: never read/write a private ivar/method of the `mcp` gem; depend only on its public API; if
  a needed distinction is not expressible publicly, track it in `rails_mcp`'s own state; any
  reliance on a specific `mcp` behavior must be pinned by a contract/drift test that fails when
  `mcp` changes it — the `~>` constraint is not a substitute. **(ARCH-01)**
- **Given** the "Allow-list only" invariant, **when** read, **then** it adds: the args allow-list
  is derived from the tool's **effective input schema** — a tool that sets a raw `input_schema`
  must still receive its declared properties in `perform`; the allow-list is the schema's
  properties, not only `arg` declarations; any escape hatch must round-trip its declared inputs to
  `perform`, verified by an invocation test. **(ARCH-02)**
- **Given** the "Allow-list only" invariant, **when** read, **then** it adds: only
  `RailsMcp::Tool` subclasses that do not override `call` carry the authorize/audit/allow-list
  guarantees; registering a bare `MCP::Tool` or overriding `call` bypasses every gem guarantee;
  the gem ships a guard/test that makes such an entry a visible, deliberate exception; a
  silently-mixed list is a product finding. **(API-01)**
- **Given** the Architecture invariants section, **when** read, **then** it adds: class-level DSL
  calls (`arg`, `read_only!`, `input_schema`) run at class-definition/boot time only; per-class
  memoized state relies on writes completing before any concurrent request-time read; do not
  introduce runtime mutation of tool class state. **(ARCH-05)**

### R8 — Public API discipline: event-contract scope, client-facing error surface

- **Given** `docs/conventions.md`'s Public API discipline section, **when** read, **then** it
  adds: the `invoke.rails_mcp` event fires only for calls that reach the tool pipeline; calls
  rejected upstream by `mcp` (schema validation, unknown tool) emit no event; never document the
  event as capturing every call; scope the invariant to the pipeline entry point and name where
  pre-pipeline rejections are captured; a test covers the schema-rejected short-circuit. **(ARCH-03)**
- **Given** the same section, **when** read, **then** it adds: the client-facing error/denial
  surface (what the AI client receives on deny, raise, and schema rejection) is part of the public
  contract and must be documented and pinned by a test. **(DOC-04)**

### R9 — Layout: error classes in `errors.rb`

- **Given** `docs/conventions.md`'s Layout section, **when** read, **then** it adds: exception
  classes live together in `lib/rails_mcp/errors.rb` (the base `Error` and its subclasses),
  required first; do not define error classes in the requires-only entry file or inline in an
  unrelated implementation file. **(ARCH-04)**

### R10 — Generated-example security rule

- **Given** `docs/conventions.md`, **when** read, **then** a **Generated example security** rule
  states: any credential-handling code the generator stamps or the docs teach MUST model the
  secure form — digest-at-rest, `ActiveSupport::SecurityUtils.secure_compare`, anchored scheme
  parse (`/\ABearer (.+)\z/`); a getting-started recipe storing/comparing a raw secret or using a
  global-gsub Bearer strip is a product finding. **(SEC-01)**

### R11 — Tests section (conventions.md): isolation, filenames, prose bans consolidated

- **Given** `docs/conventions.md`'s Tests section, **when** read, **then** it adds: every test
  file must pass in isolation (`ruby -Itest <file>`, and `-n <single>`); no test may depend on
  another having autoloaded a constant or set global state; a test references/requires every
  constant it asserts on (including lazily-autoloaded `mcp` constants); CI runs each file alone.
  **(TEST-01)**
- **Given** the same section, **when** read, **then** it adds: test filenames name the unit or
  flow under test, never a spec theme, phase, or posture word (no `*_hardening_`, `*_end_to_end_`,
  `real_world_`, `smoke_`, `sanity_`, `neutral_conduit_` names); a unit spec mirrors its `lib/`
  class path 1:1; an integration file is named for the real flow, one per flow; two test files may
  not share a basename; files under `test/rails_mcp/` mirror a `lib/rails_mcp/` class and
  docs/artifact tests live under `test/docs/`. **(TEST-04, SIMP-07)**
- **Given** the same section, **when** read, **then** it adds: one integration harness per entry
  point — the controller/`RegisteredTools` shape is exercised through the verbatim rendered-template
  fixture; do not hand-mirror the template in a second end-to-end test; source-grep guards that
  enforce an ADR constraint (no registry/`expose!`/inherited hook/jsonrpc/transport) live together
  in `test/adr_constraints_test.rb`, not scattered across unit specs. **(SIMP-03, SIMP-06)**
- **Given** the same section, **when** read, **then** it adds: tests assert runtime behavior, not
  the text of `.md` docs; a doc-vs-code cross-check (a doc snippet must match a shipped template)
  belongs in the generator/fixture suites as a template-content assertion, not in a doc-prose
  test; the instrumentation payload and event-count contract is owned by `instrumentation_test.rb`
  and a Tool test asserts only the wiring (authorize+perform run inside the single event,
  including the denial-before-perform path), not the payload shape or success/failure counts.
  **(SIMP-04, SIMP-05)**

### R12 — REVIEW.md: operationalized error-leak, extended dynamic-dispatch grep, test findings

- **Given** `REVIEW.md`'s "No secret or stack leak in a surfaced tool error" invariant, **when**
  read, **then** it is operationalized: every shipped `authorize`/`perform` example and the gem's
  default deny message must be verified against `mcp`'s `Internal error calling tool <name>:
  <e.message>` surfacing — no record ids, SQL, or internal class names in a raised message;
  developer detail belongs in the notification payload/logs; flag any `perform` example
  interpolating untrusted/internal data into a `raise`. **(SEC-02)**
- **Given** `REVIEW.md`'s "No arbitrary-Ruby/console path" invariant, **when** read, **then** it
  enumerates the dynamic-dispatch forms the grep must check: eval-family PLUS `constantize`,
  `const_get`, `public_send`, and `send`/`__send__` with a non-literal argument. **(SEC-05,
  mirrored in R15)**
- **Given** `REVIEW.md`'s Tests section, **when** read, **then** it adds: once a verbatim-template
  integration fixture exists for a flow, a second hand-mirrored integration test of the same flow
  is a finding (redundant AND diverging) even if green — delete it and migrate any unique
  assertion onto the verbatim fixture; one integration file per flow. **(TEST-03)**
- **Given** `REVIEW.md`'s Tests section, **when** read, **then** it adds: asserting that
  prose/marketing sentences appear in a `.md` file is a finding; a docs test is allowed only when
  it (a) asserts a literal code token in the doc equals the same token in shipped code (a drift
  guard) or (b) executes an example extracted from the doc and asserts its behavior; posture-named
  test files (`*_hardening_`, `real_world_`, etc.) are findings. **(TEST-05, STD-03)**
- **Given** `REVIEW.md`'s Tests section, **when** read, **then** it adds: the no-credential-in-payload
  and no-secret/stack-leak invariants must be tested on the REAL request path (a `tools/call`
  carrying an `Authorization: Bearer` through the controller), asserting the token appears in
  neither the audit payload (including nested `args`) nor the surfaced error; a scrub test whose
  input never contained the secret at the level asserted is a tautology — flag it. **(TEST-06)**

### R13 — CLAUDE.md: honest machine-enforcement, ADR integrity, pre-publish checklist

- **Given** `CLAUDE.md`'s "Machine-checkable ADR constraints" section, **when** read, **then** it
  states: a rule may be called machine-checkable/CI-enforced ONLY if a named check runs it in CI
  (cite the `file:line` or shared rake task); a local git hook is NOT CI; each constraint is
  listed with its enforcing check; adding a machine-checkable claim requires adding the check in
  the same change; shared checks are extracted into a rake task so pre-commit and CI cannot drift.
  **(SEC-04)**
- **Given** the same section, **when** read, **then** the enumerated dynamic-dispatch forms from
  R12/SEC-05 (eval-family PLUS `constantize`, `const_get`, `public_send`, non-literal
  `send`/`__send__`) are mirrored here as the coverage the ADR-0004 grep must have. **(SEC-05)**
- **Given** `CLAUDE.md`, **when** read, **then** it adds an **ADR-integrity clause**: when a new
  ADR removes/changes machinery an existing Accepted ADR describes, EVERY such earlier ADR MUST be
  re-statused (Superseded / Partially superseded) with a bidirectional link in the SAME change; a
  grep test asserts no Accepted, non-superseded ADR names a removed symbol. **(DOC-02)**
- **Given** `CLAUDE.md`, **when** read, **then** it adds a **pre-publish checklist** item: a
  public release requires `SECURITY.md` (private disclosure path) and a `CODE_OF_CONDUCT` linked
  from README; both stay in-repo but are excluded from the packaged gem (cross-ref PKG-01).
  **(DOC-03)**

### R14 — testing.md: RegisteredTools allow-list model replaces the removed registry

- **Given** `.claude/skills/spec-driven-dev/references/testing.md`, **when** read, **then** the
  stale registry references (currently line 36 "Real tool subclasses, registry, fail-closed
  authorize" and line 66 "The registry refuses an unregistered tool") are replaced by the
  `RegisteredTools.all` allow-list model; the mandatory tests become: (a) `MCP::Server` refuses a
  `tools/call` for a name not in the served array; (b) a redefined tool class rebuilds the server
  without `ToolNotUnique` (reload-safe by construction); (c) no arbitrary-Ruby/console surface;
  the "registry refuses an unregistered tool" line is removed. **(STD-04)**

### R15 — testing.md: posture-name ban, one-seam-per-file, doc-prose ban

- **Given** `.claude/skills/spec-driven-dev/references/testing.md`'s "Where a test lives" section,
  **when** read, **then** it adds: name test files and classes for the unit or seam under test
  (mirror the `lib/` path or the seam), never for a posture — no `*_hardening_`, `real_world_`,
  `smoke_`, `sanity_` files; one seam/behavior area per integration file, split grab-bags.
  **(STD-03)**
- **Given** the same doc, **when** read, **then** it adds the doc-prose rule mirrored from R12:
  asserting prose/marketing sentences appear in a `.md` file is a finding; a docs test is allowed
  only as a code-token drift guard or an executed doc example. **(TEST-05)**

---

## Non-goals (guardrails)

- No edits to any file other than the four owned documents (no `lib/`, tests, ADRs, templates,
  `README.md`, `docs/USAGE.md`, `docs/SEAMS.md`, `docs/generators.md`, gemspec). Specs 0010–0014
  own those.
- No new CI check, rake task, or grep is added here — this spec writes the rule that such a check
  must exist and cross-references SEC-04; the code specs implement it.
- No deletion of an existing correct rule; amendments replace only the specific named sentence or
  add to the named section.
- No behavior change to any gem guarantee — documentation only. The gem's fail-closed, allow-list,
  arg-dropping, one-event, per-request-identity, read/write-neutral, zero-gem-policy guarantees are
  untouched.
