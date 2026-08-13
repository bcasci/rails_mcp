# rails_mcp — agent working notes

A Ruby gem exposing selected Rails app actions to an AI client over MCP, on top of the
official `mcp` gem. The gem ships conventions and seams only; each app owns authorization,
audit, and (if it has it) tenancy. Work is organized as **specs** under `specs/`: each spec
is one capability in a numbered folder (`specs/0001-…/`) holding `spec.md` (requirements +
acceptance criteria) and `tasks.md` (the build plan). Completed specs move to
`specs/archive/`. See also `docs/adr/` (decisions).

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
- **Convention or gotcha** specific to this gem → add a line here.
- **Cross-project or behavioral** learning → user-local memory, not this repo.

No learnings bank yet — record straight to the primitive above. Add a bank only if
recurring gotchas start accumulating across the multi-app rollout.

### Machine-checkable ADR constraints

Some ADRs are standing constraints, enforced by grep in CI (not just prose):

- ADR-0001 / ADR-0004 — no hand-rolled JSON-RPC/transport, no console or arbitrary-Ruby
  tool, no gem-side policy or tenant references.

## Conventions

Project-specific naming, architecture invariants, layout, and API rules are in
[`docs/conventions.md`](docs/conventions.md) — read it before adding classes or seams.
Baseline: minitest, standardrb, read-only v1 (ADR-0003).

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
