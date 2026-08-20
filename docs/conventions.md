# Conventions — `rails_mcp`

Project-specific rules only. General Ruby/gem/Rails idioms (frozen string literals,
minitest layout, standardrb style) are assumed known and are not repeated here.
Imperative and enforced. Authoritative values live in code — this doc points, it doesn't
duplicate. Versioning and deprecation are **not** assumed known — the pre-1.0 policy is
stated below (see Versioning & deprecation).

## Versioning & deprecation

- **Pre-1.0 (`0.x`) has no compatibility guarantee.** A minor version bump MAY break a
  public seam (`authorize`/`perform` signature, event payload keys, `mount_mcp`) without a
  deprecation cycle — this is SemVer §4 (major version zero is for initial development;
  anything may change). The `0.1.0`→`0.2.0` seam changes are legitimate under this rule.
  (STD-01)
- **Every such break is recorded** in `CHANGELOG.md` under the new version (see below), and
  the README states the current stability level (`0.x`, pre-1.0, seams may change) so
  integrators are not surprised.
- **At 1.0 the frozen-contract rule activates.** From `>= 1.0`, a seam change ships the old
  and the new form together, warns on the old, and removes the old no sooner than one minor
  later — never a silent break (see Public API discipline, scoped to `>= 1.0`).
- **`CHANGELOG.md` follows Keep a Changelog.** When `lib/rails_mcp/version.rb` bumps, the
  matching `[Unreleased]` block MUST — in the same commit — be promoted to a dated
  `## [X.Y.Z] - YYYY-MM-DD` section with `Added`/`Changed`/`Removed` groupings and compare
  link refs, and a `vX.Y.Z` git tag cut. A version bump that leaves its changes under
  `[Unreleased]` is **release-blocking**. A CI check MUST assert that the current `VERSION`
  has a matching dated changelog section; adding that check is a code-spec task (cross-ref
  SEC-04 — this doc records the rule, it does not claim the check already runs). (PKG-02)

## Naming — name things what they are

- **Tools** are named for the action they expose, in the app's domain vocabulary:
  `Households::LookupTool`, not `Tool1` or `DataTool`. A reviewer reading the class name
  must know exactly what the AI can do.
- **Args** are named for the domain concept: `arg :household_id`, never `arg :id` or
  `arg :param`. The arg name is what the AI sees in the schema — it must be self-describing.
- **Seam names are a public contract** — `authorize`, `perform`, and the `invoke.rails_mcp`
  notification event. Never rename, alias, or add a synonym; apps and event subscribers
  depend on the exact spelling.
- The notification event has **one canonical name** (see SPEC R4). In gem code
  (`lib/rails_mcp/**`) the event name string appears **exactly once** — the `EVENT`
  constant (`Instrumentation::EVENT`); every other gem reference uses the constant, never
  the literal (grep-enforceable; adding that grep is a code-spec task, cross-ref SEC-04).
  **Sole exception:** a generated template MAY use the literal event string, because the
  app subscribes before the gem constant is loaded; the template must carry an inline
  comment marking the literal as an intentional exception. (STD-02)

## Architecture invariants (enforced, not aspirational)

- **The gem ships no policy.** No authorization, audit persistence, or identity resolution
  in `lib/`. If a change adds any of these to the gem it is wrong — it belongs
  in the app-owned `ApplicationMcpTool`. (ADR-0004)
- **Two seams only** — `authorize` and the notification event. Adding a third seam needs an
  ADR.
- **Allow-list only.** The sole callable surface is the `RailsMcp::Tool` subclasses the app
  lists in `RegisteredTools.all` and hands `MCP::Server.new(tools:)`. No generic executor, no
  console tool, no `eval`, no `rails runner` path. The allow-list guarantee is the `mcp`
  gem's — the array passed to `tools:` is the allow-list. (ADR-0004, ADR-0013, R10)
  - **The args allow-list is the tool's effective input schema, not only `arg` declarations.**
    A tool that sets a raw `input_schema` (the `mcp` gem's public escape hatch) must still
    receive its declared `properties` in `perform`. The allow-list that `call` filters
    against is the effective schema's properties, not the subset declared via `arg`. Any
    such escape hatch MUST round-trip every declared input to `perform`, verified by an
    invocation test that calls the tool with those inputs and asserts `perform` saw them.
    (ARCH-02)
  - **Only `RailsMcp::Tool` subclasses that do not override `call` carry the guarantees.**
    The authorize/audit/allow-list guarantees live in `Tool.call`. Registering a bare
    `MCP::Tool`, or a `RailsMcp::Tool` subclass that overrides `call`, bypasses every gem
    guarantee. The gem ships a guard/test that makes such an entry a **visible, deliberate
    exception**, never silent; a served array that silently mixes guaranteed and bypassing
    tools is a product finding. (API-01)
- **Delegate the protocol** to the official `mcp` gem. No hand-rolled JSON-RPC or transport.
  (ADR-0001)
  - **Never read or write a private ivar/method of the `mcp` gem.** Depend only on its
    public API. If a distinction the gem needs is not expressible through `mcp`'s public
    surface, track it in `rails_mcp`'s own state — do not reach into `mcp` internals. Any
    reliance on a specific `mcp` behavior MUST be pinned by a contract/drift test that fails
    when `mcp` changes it; the `~>` version constraint is **not** a substitute for such a
    test. (ARCH-01, cross-ref PKG-07)
- **Class-level DSL runs at boot only.** `arg`, `read_only!`, and `input_schema` are
  class-definition/boot-time calls. Per-class memoized state relies on those writes
  completing before any concurrent request-time read; do **not** introduce runtime mutation
  of tool class state. (ARCH-05)
- **Defaults fail closed.** An unconfigured `authorize` denies rather than allows. (R3)

## Layout

- Public entry `lib/rails_mcp.rb` holds requires only. Implementation in
  `lib/rails_mcp/<thing>.rb`, one class/module per file, file path mirrors the constant.
- Generators under `lib/generators/rails_mcp/`, their templates alongside.
- Code the generator stamps **into the app** is app-owned and editable. Code in `lib/` is
  **gem-owned** and semver-guarded — don't blur the line.
- **Exception classes live together in `lib/rails_mcp/errors.rb`** — the base
  `RailsMcp::Error` and every subclass (e.g. `NotAuthorized`) — required first. Do not
  define error classes in the requires-only entry file (`lib/rails_mcp.rb`) or inline in an
  unrelated implementation file. (ARCH-04)

## Public API discipline

- The seam signatures — `authorize`'s and `perform`'s keyword args, the event payload keys —
  are **frozen contracts at `>= 1.0`**: from 1.0 on, change them only through a deprecation
  cycle, never a silent break. Below 1.0 the `0.x` policy applies (see Versioning &
  deprecation) — a minor MAY break them, recorded in `CHANGELOG.md`. This scoping is why the
  `0.1.0`→`0.2.0` seam break is not a violation.
- Anything not intended as public API lives under an internal module or is marked
  `@api private`.
- **The `invoke.rails_mcp` event fires only for calls that reach the tool pipeline.** Calls
  rejected upstream by `mcp` (schema validation failure, unknown tool) never reach
  `Tool.call` and emit **no** event. Never document the event as capturing every call; scope
  the invariant to the pipeline entry point (`RailsMcp::Tool.call`) and name where
  pre-pipeline rejections are otherwise observed (the transport/`mcp` layer). A test covers
  the schema-rejected short-circuit (no event fired). (ARCH-03)
- **The client-facing error/denial surface is part of the public contract.** What the AI
  client receives on `authorize` deny, on a `perform` raise, and on `mcp` schema rejection
  MUST be documented and pinned by a test. (DOC-04)

## Tests

- One behavior per test. Mirror SPEC acceptance criteria: Given/When/Then maps to
  arrange/act/assert, one requirement's criterion per test.
- **Real objects by default.** Stubs and mocks are for true external boundaries only (network,
  clock, randomness) and must earn their place; never mock the unit under test or the gem's
  own classes, and assert on outcomes, not on "a method was called." Full discipline in the
  `spec-driven-dev` skill's `references/testing.md`.
- **Every test file passes in isolation.** `ruby -Itest <file>` (and `-n <single>`) must pass
  standalone; no test may depend on another having autoloaded a constant or set global state.
  A test references/requires every constant it asserts on — including lazily-autoloaded `mcp`
  constants. CI runs each file alone. (TEST-01)
- **Test filenames name the unit or flow under test — never a spec theme, phase, or posture
  word.** Banned name fragments: `*_hardening_`, `*_end_to_end_`, `real_world_`, `smoke_`,
  `sanity_`, `neutral_conduit_`. A unit spec mirrors its `lib/` class path 1:1 — files under
  `test/rails_mcp/` mirror a `lib/rails_mcp/` class. An integration file is named for the
  real flow, one file per flow. Two test files may not share a basename. Docs/artifact tests
  live under `test/docs/`. (TEST-04, SIMP-07)
- **One integration harness per entry point.** The controller/`RegisteredTools` shape is
  exercised through the verbatim rendered-template fixture (`test/integration/fixture_app/`);
  do not hand-mirror the template in a second end-to-end test. Source-grep guards that enforce
  an ADR constraint (no registry / `expose!` / inherited hook / JSON-RPC / transport) live
  together in `test/adr_constraints_test.rb`, not scattered across unit specs. (SIMP-03,
  SIMP-06)
- **Tests assert runtime behavior, not the text of `.md` docs.** A doc-vs-code cross-check
  (a doc snippet must match a shipped template) belongs in the generator/fixture suites as a
  template-content assertion, not in a doc-prose test. The instrumentation payload and the
  event-count contract are owned by `instrumentation_test.rb`; a `Tool` test asserts only the
  wiring — that `authorize` + `perform` run inside the single event, including the
  denial-before-`perform` path — not the payload shape or the success/failure counts.
  (SIMP-04, SIMP-05)

## Integration reality (this gem is a library over Rails)

The gem's real failures live in the seam between it and a running app — dev reload, production
`Host`, `ApplicationController` middleware — where the gem's own unit
tests don't reach. Build and spec for that seam; don't leave it for review to catch.

- **Test the artifact, not a copy.** An integration test loads the actual generated/stamped
  output (rendered `.tt` templates), never a hand-mirrored or stubbed stand-in. If a test must
  *add* something to pass (an `allowed_hosts`, a header) or *swap* a base class
  (`ActionController::Base` for the app's real `ApplicationController`), that delta is a
  **product finding** — the divergence hides the bug it claims to cover.
- **Exercise the host framework's real defaults.** A real `ApplicationController` (CSRF,
  inherited `before_action`s), a Zeitwerk reload cycle, and a production `Host` header. Bare
  base classes hide exactly the integration failures that ship. (See
  `test/integration/fixture_app/` — the verbatim template fixture — as the pattern.)
- **Write integration-hazard criteria before coding.** For any spec on the gem↔app seam, add
  acceptance criteria for: dev reload (Zeitwerk), cold boot, production host/proxy, and
  host-framework middleware. "The tests are green"
  is necessary, not sufficient — a concern with no criterion is invisible to review.
- **Test stamped config defaults at their production default, not a test-populated value.**
  A stamped default that reads a Rails config value (`config.hosts`, etc.) MUST be tested
  with that value at its **production default** (e.g. empty), not a value the fixture added.
  If the fixture has to add the value for the test to pass, the default is a **product
  finding** — the test is proving a configuration the shipped app won't have. (SEC-03)
- **The verbatim-fixture rule covers every stamped file the end-to-end call touches —
  including the example tool.** Each stamped file the fixture loads carries a
  source-equals-template guard test (rendered output equals the `.tt`). A fixture tool
  exercised by an HTTP proof MUST be loaded from its `.tt` and guarded, and the call MUST
  supply the template's required args. A `const_set` (or other in-test) stand-in for a
  stamped class **is** the divergence this rule forbids. (TEST-02, cross-ref DOC-05)
- **Every documented HTTP handshake/curl recipe is backed by an integration test** that runs
  the exact request sequence against the verbatim fixture. A doc step describing an error the
  shipped transport cannot emit, or a handshake step it does not require, is a **product
  finding**. Handshake instructions MUST match the transport ADR (ADR-0002, stateless — no
  session/init handshake the transport doesn't require). (DOC-01)

## Packaging (public gem)

This gem is published to RubyGems. The package is a public artifact — treat its file list
and metadata as part of the security and public-API surface.

- **`spec.files` is an explicit allowlist of runtime paths only — never a denylist.** This is
  a **security rule**: shipping the control catalog (`REVIEW.md`, `.githooks/`, `docs/adr/`,
  `specs/`, `.claude/`) leaks how the gem is defended and reviewed. Enumerate the runtime
  paths (`lib/`, `README.md`, `LICENSE`, `CHANGELOG.md`) explicitly; do not glob the repo and
  subtract. A test MUST assert the built gem's file list **excludes** every internal path.
  In-repo-but-excluded also covers `SECURITY.md` and `CODE_OF_CONDUCT` (cross-ref DOC-03).
  (PKG-01)
- **Required gemspec metadata.** The gemspec MUST set `homepage_uri`, `source_code_uri`,
  `changelog_uri`, `bug_tracker_uri`, and `rubygems_mfa_required = 'true'`. (PKG-04)
- **The summary/description is public API copy.** The gemspec `summary`/`description` MUST
  match the current README one-liner and must not reference a removed concern. When an ADR
  removes a capability, the gemspec description is part of that change's surface — update it
  in the same change. (PKG-03)
- **Ship `sig/` only if it types the public API and is validated in CI.** A default/generated
  RBS stub MUST NOT be shipped — remove it until real types exist and are CI-checked. Any use
  of a dependency's **private** API requires both an upper version bound in the gemspec AND a
  drift test that fails when the internal name disappears (cross-ref ARCH-01). (PKG-07)
- **CI matrix.** CI MUST test the full declared support range — every minor Ruby from
  `required_ruby_version` up to current stable (including the `.tool-versions` dev Ruby), and
  the min + latest of each Rails major covered by the dependency floors. A change to
  `required_ruby_version` or a dependency floor MUST update the matrix in the **same** change.
  Single-version CI is insufficient for a public gem. (CI-01, cross-ref SEC-04 — this doc
  records the rule; the workflow change is a code-spec task.)

## Generated example security

Anything the generator stamps or the docs teach is a template a developer will copy. It MUST
model the secure form, because getting-started code is the code that gets pasted into
production.

- **Credential handling in stamped/taught code models the secure form:** digest-at-rest (never
  a raw secret stored or compared), constant-time comparison via
  `ActiveSupport::SecurityUtils.secure_compare`, and an **anchored** scheme parse
  (`/\ABearer (.+)\z/`), never a global-`gsub` `"Bearer "` strip. A getting-started recipe that
  stores or compares a raw secret, or strips the scheme with an unanchored `gsub`, is a
  **product finding**. (SEC-01)
