# TASKS — `rails_mcp` v1 build

Task breakdown for a **parallel multi-agent build**. Hard constraint: **each task owns a
DISJOINT set of files** — no two tasks touch the same file, so agents build concurrently
without merge conflicts. Shared entry points (the gem's main require file, the gemspec) are
owned by a single foundation task; dependents add their own files and are wired in by that
owner or via a documented require the dependent adds to its own file only.

Every task is `autonomous` — all decisions are locked as `DECIDED` in spec.md, so the build
runs unattended. References like `R3` point to spec.md requirements.

The top-level constant is `RailsMcp` and the tool dir is `app/mcp/`.

---

## Layer 0 — Foundation (must land first)

### T0 — Gem skeleton, gemspec, dependency on official `mcp`
**Owns:**
- `rails_mcp.gemspec`
- `Gemfile`
- `lib/rails_mcp.rb` (top-level require + `RailsMcp` module namespace; requires submodules)
- `lib/rails_mcp/version.rb`
- `.gitignore`, `Rakefile`
- `README.md` (gem-level, minimal)
- `test/test_helper.rb`

**Depends on:** none.
**Acceptance (R12):**
- Gemspec declares the official `mcp` gem as a pinned dependency; `bundle install` succeeds.
- `require "rails_mcp"` loads without error and exposes the `RailsMcp` namespace.
- No hand-rolled JSON-RPC/transport in the gem (delegated to `mcp`).
- `rake` runs the (initially empty) test suite green.

**Tag:** `autonomous` — gem name/namespace, Ruby/Rails floor, and engine are all DECIDED in
spec.md.

> `lib/rails_mcp.rb` is owned solely by T0. Later tasks add their own files under
> `lib/rails_mcp/` and are required from `lib/rails_mcp.rb`; to keep files disjoint, T0
> stubs the require lines for all planned submodules up front so no later task edits it.

---

## Layer 1 — Core tool primitives (parallel after T0)

### T1 — Args DSL
**Owns:**
- `lib/rails_mcp/args.rb` (the `arg` class macro, type registry, schema builder)
- `test/rails_mcp/args_test.rb`

**Depends on:** T0.
**Acceptance (R1):**
- `arg :x, :integer, required: true` contributes `x` as a required integer to the input
  schema.
- Missing required arg is rejected before `perform`; wrong-typed arg is rejected.
- Undeclared args are not forwarded to `perform`.

**Tag:** `autonomous` — R1 validation engine DECIDED (official gem's `input_schema`).

### T2 — Annotations DSL (`read_only!` etc.)
**Owns:**
- `lib/rails_mcp/annotations.rb` (`read_only!` → `readOnlyHint`, tier declaration, default
  = unannotated/dangerous)
- `test/rails_mcp/annotations_test.rb`

**Depends on:** T0.
**Acceptance (R5):**
- `read_only!` sets `readOnlyHint: true` on the advertised tool.
- No annotation ⇒ tool is not treated as read-only (maximally dangerous default).

**Tag:** `autonomous` — R5 tier enforcement DECIDED (deferred; v1 read-only). Build-time:
verify the pinned `mcp` version emits annotations, pin one that does.

### T3 — Notifications (audit seam)
**Owns:**
- `lib/rails_mcp/instrumentation.rb` (emits one `ActiveSupport::Notifications` event per
  call; payload builder; explicitly excludes credentials)
- `test/rails_mcp/instrumentation_test.rb`

**Depends on:** T0.
**Acceptance (R4):**
- Exactly one event per invocation (success or failure).
- Success payload carries staff user, tool name, args, result marker; failure payload
  records the error.
- Gem persists nothing; no bearer token in payload.

**Tag:** `autonomous` — R4 event name `invoke.rails_mcp` + payload schema DECIDED;
credentials excluded (enforced).

---

## Layer 2 — Tool base class (integrates Layer 1)

### T4 — `RailsMcp::Tool` base class (perform, authorize, invoke pipeline)
**Owns:**
- `lib/rails_mcp/tool.rb` (base class; includes Args T1, Annotations T2; wraps invoke as
  authorize → perform → notify; `text_response` helper; fail-closed default `authorize`)
- `test/rails_mcp/tool_test.rb`

**Depends on:** T1, T2, T3.
**Acceptance (R2, R3):**
- `perform(**args)` receives declared args and its return value is the tool result;
  `text_response("ok")` yields a text result.
- Default `authorize` fails closed (denies) unless overridden; on deny, `perform` never
  runs.
- Authorize runs before perform; the T3 notification fires exactly once per invoke,
  including on raise.

**Tag:** `autonomous` — R3 `authorize(user:, args:, tool:)` DECIDED; R11 no tenant seam
DECIDED.

---

## Layer 3 — Transport mount (parallel with Layer 2, depends only on T0)

### T5 — `mount_mcp` route helper + Rack transport wiring
**Owns:**
- `lib/rails_mcp/mount.rb` (the `mount_mcp` routing helper over the official gem's Rack
  transport)
- `lib/rails_mcp/registry.rb` (registered-tool set; the allow-list surface)
- `test/rails_mcp/mount_test.rb`
- `test/rails_mcp/registry_test.rb`

**Depends on:** T0. (Integrates with T4 tools at runtime via the registry, but shares no
files with T4.)
**Acceptance (R6, R10):**
- `mount_mcp '/mcp'` mounts an MCP endpoint in-process; `tools/list` returns only
  registered tools.
- `tools/call` on an unregistered tool is refused.
- No arbitrary-Ruby/console tool exists in the surface.

**Tag:** `autonomous` — R6 stateless HTTP DECIDED.

---

## Layer 4 — Install generator (depends on the runtime API shape from Layers 2–3)

### T6 — `rails g rails_mcp:install` generator + templates
**Owns:**
- `lib/generators/rails_mcp/install/install_generator.rb`
- `lib/generators/rails_mcp/install/templates/application_mcp_tool.rb.tt` (fail-closed,
  commented authorize + audit seams; optional commented scoping note, no tenant presumption)
- `lib/generators/rails_mcp/install/templates/initializer.rb.tt`
- `lib/generators/rails_mcp/install/templates/example_read_only_tool.rb.tt`
- `lib/generators/rails_mcp/install/templates/example_tests.rb.tt` (authz denial,
  audit-row-written)
- `lib/generators/rails_mcp/install/templates/routes_mount.rb.tt` (the `mount_mcp` line)
- `test/generators/install_generator_test.rb`

**Depends on:** T4 (base class API), T5 (`mount_mcp`, registry). Templates reference those
public APIs but do not edit their files.
**Acceptance (R7, R8, R9, R11):**
- Generator creates the app-owned `ApplicationMcpTool`, an initializer, the `/mcp` route
  line, one read-only example tool, and example tests.
- The stamped `ApplicationMcpTool` is fail-closed with clearly marked authorize + audit
  seams (no presumed tenancy; scoping is a commented, optional note).
- Example tests express authz denial and audit-row-written.

**Tag:** `autonomous` — R8 generator paths, R7 seam contract, R9 context shape all DECIDED
in spec.md.

---

## Layer 5 — Cross-cutting verification & docs (after all above)

### T7 — Integration test: allow-list + fail-closed + audit end-to-end
**Owns:**
- `test/integration/end_to_end_test.rb`
- `test/integration/dummy_app/` (minimal dummy Rails app harness for mounting: routes,
  config, a stub `ApplicationMcpTool`, a stub staff user + stub tenant — all app-side
  stubs, not gem code)

**Depends on:** T4, T5, T6.
**Acceptance (R3, R4, R9, R10, R11 integrated):**
- Through a mounted `/mcp`, only registered read-only tools are callable.
- An unauthorized/unresolved-identity call fails closed; an authorized call runs and emits
  exactly one audit event attributed to the real staff user.
- A cross-tenant attempt is denied by the dummy app's wiring (proving the seam is
  usable, not that the gem enforces tenancy).

**Tag:** `autonomous` (given the seams' contracts are frozen by T3/T4/T6 oracle decisions).

### T8 — Gem usage docs (developer-facing)
**Owns:**
- `docs/USAGE.md` (how to install, wire the seams, write a read-only tool)
- `docs/SEAMS.md` (the frozen `authorize` + notification contracts, context-object shape)

**Depends on:** all API-freeze decisions (T3, T4, T6). Documents only; no gem code.
**Acceptance:**
- Docs reflect the frozen event name/payload (R4), `authorize` signature (R3), and context
  shape (R9) exactly as built.

**Tag:** `autonomous` — contracts (R3/R4/R9) are frozen in spec.md; docs reflect them.

---

## Dependency graph (build order)

```
T0
├─ T1 ┐
├─ T2 ┼─→ T4 ─┐
├─ T3 ┘       ├─→ T6 ─→ T7
└─ T5 ────────┘        └─→ T8
```

Layer 1 (T1/T2/T3) and T5 run in parallel after T0. T4 waits on T1/T2/T3. T6 waits on
T4+T5. T7/T8 last.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**

- Gem name / namespace: `rails_mcp` / `RailsMcp`.
- Version floor: Ruby 3.2+, Rails 7.1+.
- Engine: official `mcp` gem. No `action_mcp` spike.
- Transport: HTTP only in v1, stateless (`mount_mcp`). No stdio.
- Tenancy: the gem has no tenant seam and no tenant concept; not presumed multi-tenant.
  Only frozen seams are `authorize` and the notification event.
- Args validation: use the official gem's JSON-Schema `input_schema`.

**DECIDED (design details, also locked in spec.md):**

- Annotations tier enforcement: deferred (v1 read-only) — T2 (R5). Build-time: verify the
  pinned `mcp` emits annotations.
- Event `invoke.rails_mcp`; payload `{user, tool, args, result-or-error}`, no credentials — T3 (R4).
- `authorize(user:, args:, tool:)` — T4 (R3).
- Generator paths: `app/mcp/`, `config/initializers/rails_mcp.rb`, example tool — T6 (R8).
- Context object: gem wrapper with `user:`, no tenant, no raw token — T6 (R9).

No open decisions remain — every task is `autonomous`; the build runs unattended.
