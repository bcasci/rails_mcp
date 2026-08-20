# rails_mcp — agent working notes

A Ruby gem exposing app-defined tools to an MCP client, on top of the official `mcp` gem.
Work is organized as **specs** under `specs/`: each spec is one capability in a numbered
folder (`specs/0001-…/`) holding `spec.md` (requirements + acceptance criteria) and
`tasks.md` (the build plan). Completed specs move to `specs/archive/`. See also `docs/adr/`
(decisions).

## Scope — what this gem is (and is NOT) — ADR-0012

The gem registers app-defined tools, exposes them over MCP, calls `authorize` before each
tool runs, and emits one `invoke.rails_mcp` notification per call. That is all it does. It
imposes **no policy of its own**. These are **implementor decisions**, made in the app's
tool/controller/app code — the gem takes no position and must ship no opinion on any:

- **read vs write** (a tool's `perform` may do anything; `read_only!` is an optional advisory
  annotation, not a gate — the gem does not enforce read-only),
- **who may call / how they authenticate** (the app's `McpController`),
- **permissions** (the app's `authorize`),
- **audience** (internal operators, end-users, anything),
- **tenancy, persistence, audit sink** (app code).

Any proposed change that decides one of those *for* the app is out of scope — remove it.
Default to removal; when a request is ambiguous about scope, ask one question before building.

## Building (the factory)

- Implement a task with the `spec-driven-dev` skill: read the task in its spec's `tasks.md`
  + the referenced requirements in `spec.md`, test-first from the acceptance criteria,
  implement to green, run the gate.
- `/implement` (`.claude/workflows/implement.js`) builds a whole spec autonomously: a planner
  resolves the spec folder and derives the dependency-ordered layers, builder agents run per
  task, a per-layer gate + heal loop, a **Verify loop** (an independent reviewer + an
  independent auditor — neither the builder — run together against `REVIEW.md` and the spec;
  a fix pass clears blocker/major findings; re-verify until both are clean or a 3-round cap
  stops for a human), a reflect stage, and an archive that moves the finished spec to
  `specs/archive/`. `/implement 0001` builds one spec; `/implement 0001 T3` builds one task.
- `/code-review --fix` (guided by `REVIEW.md`) is an optional human spot-check on top of the
  autonomous review phase — the build no longer needs it. Never self-certify.
- Naming/architecture/testing rules: `docs/conventions.md`. Generator specifics:
  `docs/generators.md`.

## Specs

- One spec = one capability whose tasks depend only on each other and on already-shipped
  code. Tasks with build-time dependencies stay in the same spec. A new capability that
  builds on shipped code gets its own numbered spec — never grow one spec into a monolith.
- Numbering is monotonic (`0001`, `0002`, …), same scheme as `docs/adr/`; an archived spec
  keeps its number.

## Recording decisions and learnings

A `Stop` hook nudges once per session to record durable knowledge. Route it:

- **Decision** — architecturally significant and hard to reverse: a new/replaced
  dependency, a change to a public seam (`authorize`, the notification payload,
  `mount_mcp`), or a structural choice. → Write an **ADR** in `docs/adr/`, numbered, using
  the Nygard template (Status / Context / Decision / Consequences). Write it at decision
  time, not reconstructed. ADRs are immutable once Accepted — to change one, add a new ADR
  that supersedes it and link both ways.
  - **ADR-integrity clause:** when a new ADR removes or changes machinery an existing
    **Accepted** ADR describes, EVERY such earlier ADR MUST be re-statused (`Superseded` or
    `Partially superseded`) with a **bidirectional link** to the new one, in the **same
    change** that lands the new ADR — never left as a stale Accepted ADR describing a removed
    symbol. A grep test asserts that no Accepted, non-superseded ADR names a removed symbol
    (a symbol no longer present in `lib/`); adding that check is a code-spec task, cross-ref
    SEC-04. (DOC-02)
- **Convention or gotcha** specific to this gem → add a line here.
- **Cross-project or behavioral** learning → user-local memory, not this repo.

No learnings bank yet — record straight to the primitive above. Add a bank only if
recurring gotchas start accumulating across the multi-app rollout.

### Machine-checkable ADR constraints

Some ADRs are standing constraints. A rule may be called **machine-checkable** or
**CI-enforced** ONLY if a **named check runs it in CI** — cite the check's `file:line` or the
shared rake task that runs it. A local git hook (`.githooks/pre-commit`) is **NOT CI**: it can
be bypassed or skipped and does not gate a merge, so a hook-only rule is not machine-checkable.
Each constraint below is listed with its enforcing check; adding a machine-checkable claim
requires adding the check **in the same change**. Shared checks are extracted into a **rake
task** invoked by both `.githooks/pre-commit` and CI, so the two cannot drift. (SEC-04 —
adding/wiring the actual CI checks is a code-spec task; this section states the rule, it does
not assert every check below already runs in CI.)

- ADR-0001 / ADR-0004 — no hand-rolled JSON-RPC/transport, no console or arbitrary-Ruby
  tool, no gem-side policy or tenant references.
- ADR-0004 dynamic-dispatch coverage — the arbitrary-Ruby grep MUST cover, over `lib/`, the
  full set of dynamic-dispatch forms, not just the eval family: `eval`, `instance_eval`,
  `class_eval`, `module_eval`, `binding` (eval-family) **PLUS** `constantize`, `const_get`,
  `public_send`, and `send`/`__send__` called with a **non-literal** argument. (SEC-05,
  mirrored from `REVIEW.md`.)
- ADR-0010 — no tenancy on the shipped surface: `grep -ri 'tenant\|shard\|multitenan'` over
  `lib/`, `docs/` (excluding `docs/adr/`), and `README.md` returns nothing.
- ADR-0015 — no `mcp` private internals in `lib/`: `grep -rn "@input_schema_value" lib/`
  returns nothing. Not yet a CI grep — its guardrail is the public-contract **drift test**
  `test/rails_mcp/mcp_contract_test.rb`, which fails if a `bundle update mcp` changes the
  public behavior the args allow-list relies on.

## Gotchas

- Args allow-list = the tool's **effective** input schema, not its `arg` list. A tool that
  sets a raw `input_schema(...)` and declares no `arg` still round-trips its schema
  properties to `perform` — the allow-list is `input_schema.to_h[:properties]` keys when a
  schema was set explicitly, else `declared_arg_names` (`RailsMcp::Args#effective_arg_names`).
  Undeclared args are dropped either way. Never re-derive the allow-list from `arg`
  declarations alone; that was the ARCH-02 data-loss bug.
- The explicit-schema distinction lives in rails_mcp's own `@explicit_input_schema` class
  flag (set by the `input_schema` setter override), not in any `mcp` ivar (ADR-0015).

## Pre-publish checklist (public release)

Before cutting a public release, in addition to the versioning/changelog rules in
`docs/conventions.md`:

- The repo carries a `SECURITY.md` (a private vulnerability-disclosure path) and a
  `CODE_OF_CONDUCT` linked from the README. Both stay **in-repo** but are **excluded from the
  packaged gem** — they are project-governance files, not runtime paths, so the `spec.files`
  allowlist must not ship them (cross-ref PKG-01). (DOC-03)

## Conventions

Project-specific naming, architecture invariants, layout, and API rules are in
[`docs/conventions.md`](docs/conventions.md) — read it before adding classes or seams.
Baseline: minitest, standardrb, neutral MCP conduit (ADR-0012).

Gotchas:

- Acting identity rides the SDK's `server_context`, not a gem-defined wrapper (ADR-0005).
  The SDK invokes a tool as `Tool.call(**arguments, server_context:)`; the app sets
  `server.server_context = {user: ...}`, the gem reads `user:` out of it. Do not add a
  `RailsMcp::Context`/identity wrapper class. The frozen contract is the keyword surface
  (`authorize(user:, args:, tool:)`, payload `{user, tool, args, result|error}`), not the
  transport of it.
- Per-request identity is isolated by building a FRESH `MCP::Server` per request INLINE in the
  generated `McpController#handle`, passing `server_context: {user: user}` at construction, then
  serving via `StreamableHTTPTransport#handle_request(request)` — all public `mcp` API. Never
  mutate a shared, boot-time server (thread-unsafe under Puma; ADR-0008). There is no
  `RailsMcp.serve`, `mount_mcp`, or `RailsMcp.rack_app` — spec 0003 removed them (ADR-0008
  supersedes ADR-0006's serve mechanism). A bare no-per-user mount, if ever needed, is one line
  of public `mcp` (`mount transport => "/mcp"`), not a gem feature.
- No `mcp` private reach anywhere in `lib/`: no `instance_variable_get(:@server)`. The old
  `serve` reached the server that way because the pinned `mcp` had no public setter; the public
  controller pattern (`MCP::Server.new(server_context:)` per request) removes the need. This is
  a machine-checkable standing constraint (ADR-0008) — keep `lib/` free of `mcp` internals.
- The DSL yields to an explicitly-set `input_schema`/`annotations` (ADR-0007): `Args#input_schema`
  is both getter and setter (`input_schema(properties:, required:)` delegates to the `mcp` macro
  and records `@input_schema_value`; the no-arg getter returns that explicit value or builds from
  `arg`s). Gotcha: `MCP::Tool.to_h` and the call path read `input_schema_value`, NOT the
  `input_schema` getter — so `Args` must also override `input_schema_value` to return the
  `arg`-built schema, or an `arg`-only tool advertises an empty schema. When bumping `mcp`,
  re-check that `to_h`/the call path still read `input_schema_value`.
- The verbatim-template fixture (spec 0005 R6, `test/integration/fixture_app/boot.rb`) proves the
  generated `McpController`/`ApplicationMcpTool` are exercised as-stamped by `eval`-ing the raw
  `.tt` at `TOPLEVEL_BINDING` and asserting the loaded constant's source is byte-identical to the
  file. This works ONLY because those two templates carry no ERB tags (`<%…%>`), so the file IS
  the rendered output. Gotcha: adding an ERB tag to either template breaks the `eval` and voids
  the R6 fidelity guarantee — if a template must become dynamic, render it through the generator's
  ERB in-suite instead of `eval`-ing the source. (The `eval` is test-only; the ADR-0004 "no `eval`"
  constraint is about gem `lib/` shipping a code-executor tool and stays intact — `grep eval lib/`
  is still empty.)
