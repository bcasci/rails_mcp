# TASKS — strip tenancy from the shipped surface

Completed Thu Aug 13 12:20:59 EDT 2026 at commit 24943ec

Task breakdown for spec 0006. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0005 (archived). References like `R1` point to this spec's `spec.md`. Governing decision:
ADR-0010. Tasks T1–T4 are independent (disjoint files), parallel; T5 is the gate, after all.

Every task is `autonomous` — decisions locked in spec.md / ADR-0010.

---

## Layer 0 — Strip (parallel, disjoint files)

### T1 — Controller template + lib header + generator test — DONE
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED: replace the
  tenant/shard scoped-context block with the neutral, tenancy-free fact — `authorize` runs
  before `perform`; wrap `handle_request` to scope a whole call; unscoped default is fine.
  Keep `skip_forgery_protection` and `allowed_hosts: Rails.application.config.hosts.grep(String)`
  unchanged — ADR-0011)
- `lib/rails_mcp.rb` (CHANGED: header lines ~8–9 drop "and any tenant scoping"; keep the
  `(ADR-0004)` reference verbatim)
- `test/generators/install_generator_test.rb` (CHANGED: delete the tenancy template-string
  tests — `test_mcp_controller_documents_with_shard_wrap`,
  `test_mcp_controller_shard_wrap_is_commented_not_active`, `test_no_active_tenant_code_stamped`;
  KEEP the host-guard tests `test_mcp_controller_passes_allowed_hosts_from_config`,
  `test_mcp_controller_filters_config_hosts_to_strings`)

**Depends on:** shipped 0001–0005.
**Acceptance (R1, R2):** controller documents the neutral fact with no tenancy words; lib header
scrubbed; generator tests green without the tenancy assertions.
**Tag:** `autonomous`.

### T2 — `ApplicationMcpTool` template — DONE
**Owns:**
- `lib/generators/rails_mcp/install/templates/application_mcp_tool.rb.tt` (CHANGED: delete the
  entire `TENANT SCOPING (optional — only if your app is multi-tenant)` comment block)

**Depends on:** shipped. Independent of T1/T3/T4.
**Acceptance (R2):** no tenancy how-to remains in the stamped base tool.
**Tag:** `autonomous`.

### T3 — Docs scrub (USAGE, SEAMS, README, conventions, generators, generator .rb comment) — DONE
**Owns:**
- `docs/USAGE.md` (CHANGED: delete `## 6. Tenancy …` section entirely, including the
  `with_shard` example and the "Recovering the tenant in the audit subscriber" subsection;
  **also scrub the intro line ~6 "and any tenant scoping"**)
- `docs/SEAMS.md` (CHANGED: remove the tenant-seam prose and the anchors pointing at USAGE §6,
  in the same pass so no dangling anchor remains; the seam list names only `authorize` and the
  `invoke.rails_mcp` event; keep the non-tenancy §5a anchor)
- `README.md` (CHANGED: remove the two one-line tenancy mentions)
- `docs/conventions.md` (CHANGED: remove/neutralize the multitenancy/sharding lines — the
  test-reality "second app profile" example must not name tenancy; and correct the stale seam
  list so it names only `authorize` + the `invoke.rails_mcp` event, not the removed `mount_mcp`)
- `docs/generators.md` (CHANGED: remove the tenancy design-constraint line; remove the stale
  `mount_mcp` helper references — the generator injects the `match "/mcp" => "mcp#handle"` line
  via the `route` helper; route-guidance asserts `mcp#`, not `mount_mcp`)
- `lib/generators/rails_mcp/install/install_generator.rb` (CHANGED: remove the tenancy word in
  the desc/comment)

**Depends on:** shipped. Independent of T1/T2/T4.
**Acceptance (R1, R5):** the victory grep is clean across docs; no dangling USAGE §6 anchor; no
`mount_mcp`/`serve`/`rack_app` references remain.
**Tag:** `autonomous`.

### T4 — Tests + fixtures: remove tenancy-only, keep the rest green — DONE
**Owns:**
- `test/rails_mcp/tenant_guidance_docs_test.rb` (DELETE — 8 pure doc-string assertions, zero
  invoke behavior)
- `test/integration/real_world_hardening_test.rb` (CHANGED — SURGICAL: delete
  `DOCUMENTED_SHARD_WRAP`, `ShardObservingTool`, `ShardWrappingController`, the two shard tests
  (`test_shard_wrap_covers_both_authorize_and_perform`,
  `test_documented_shard_wrap_matches_the_template_guidance`), **and the shard references in the
  shared `setup` block** (`ShardObservingTool.authorize_shard = nil` / `.perform_shard = nil`)
  so kept tests do not raise `NameError`. KEEP the CSRF, Host-guard both-directions, reload, and
  fail-closed tests. Do NOT delete the file.)
- `test/integration/fixture_app/tenant.rb` (DELETE)
- `test/integration/fixture_app/current.rb` (DELETE)
- `test/integration/fixture_app/boot.rb` (CHANGED: drop `require_relative "tenant"`, the
  `FixtureApp::Current` alias/setup, and the sharded-tenant comment)
- `test/integration/dummy_app/` (DELETE the whole directory — orphaned since spec 0005's
  `fixture_app` replaced it; confirm nothing requires it)

**Depends on:** shipped. Independent of T1/T2/T3 (disjoint files).
**Acceptance (R4, R5):** only tenancy-only tests removed; CSRF/Host/reload/fail-closed still
pass; `dummy_app/` gone.
**Tag:** `autonomous`.

---

## Layer 1 — Gate

### T5 — Full gate + tenancy-clean proof — DONE
**Owns:** (no new files; runs the gate)
**Depends on:** T1, T2, T3, T4.
**Acceptance (R1, R3, R4):**
- `bundle exec rake` (minitest + standardrb) is green.
- `grep -ri 'tenant\|shard\|multitenan'` over `lib/`, `docs/` (excluding `docs/adr/`), and
  `README.md` returns nothing.
- `docs/adr/0004-*.md` and `docs/adr/0005-*.md` are unchanged.
- (Note: there is no separate ADR-grep CI test in this repo; the tenancy-clean grep above is the
  spec's own gate, run in this task.)

**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0005)
T1 ┐
T2 ┤
T3 ┼─→ T5
T4 ┘
```

T1–T4 parallel (disjoint files); T5 gates.

---

## Decisions

**DECIDED (locked in spec.md / ADR-0010 — do not relitigate):**
- Tenancy removed from the shipped surface; one neutral tenancy-free pipeline-ordering fact kept.
- `real_world_hardening_test.rb` edited surgically incl. the shared `setup` block; kept tests
  stay green.
- `lib/rails_mcp.rb` and `docs/USAGE.md` intro drop "and any tenant scoping"; `(ADR-0004)` kept.
- `dummy_app/` deleted; stale `mount_mcp` doc references corrected.
- Immutable ADRs 0004/0005 untouched; no gem runtime change.

No open decisions remain — every task is `autonomous`.
