# TASKS — Packaging, CI & release metadata

Completed Wed Aug 19 23:39:21 EDT 2026 at commit c9f9058

All tasks delivered:
- [x] T1 — Gemspec allowlist + metadata + drop sig/, and the packaging test
- [x] T2 — CHANGELOG: promote [Unreleased] to dated 0.2.0 + link refs
- [x] T3 — CI matrix + per-Rails gemfiles
- [x] T4 — SECURITY.md, README links, CODE_OF_CONDUCT fix
- [x] T5 — Full gate

Task breakdown for spec 0010. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0009 (archived). References like `R1` point to this spec's `spec.md`.

Every task is `autonomous`. T1–T4 are independent (disjoint files) and parallel; T5 (gate)
depends on all of them. The one shared file is `test/packaging_test.rb` (NEW) — it is owned
solely by T1 so its assertions land in one place; T2/T3 provide the artifacts those assertions
check, but do not edit the test file.

Ownership boundary: this spec fixes code/tests/docs ONLY. No task edits `docs/conventions.md`,
`CLAUDE.md`, `REVIEW.md`, or the `spec-driven-dev` skill — all standards amendments from the
assigned findings are tracked in spec 0015.

---

## Layer 0 — Gemspec, CHANGELOG, CI, community-health docs (parallel, disjoint files)

### T1 — Gemspec allowlist + metadata + drop sig/, and the packaging test
**Owns:**
- `rails_mcp.gemspec` (CHANGED: replace the `git ls-files` reject-denylist with an explicit
  allowlist `Dir.glob("lib/**/*") + %w[README.md CHANGELOG.md LICENSE.txt]` filtered to existing
  files; fix `spec.description` "tenant scoping" → "identity"; add
  `spec.metadata["rubygems_mfa_required"] = "true"` and
  `spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"`)
- `sig/rails_mcp.rbs` (DELETE), `sig/` (DELETE dir if empty)
- `test/packaging_test.rb` (NEW: asserts the packaged `spec.files` includes the runtime files and
  excludes every internal prefix/path from R1; asserts the metadata keys/values from R6; asserts
  `RailsMcp::VERSION` has a matching dated `## [VERSION] - DATE` section in `CHANGELOG.md` and is
  not only under `[Unreleased]`, per R4)

**Depends on:** shipped 0001–0009.
**Acceptance (R1, R2, R4, R5, R6, R8):**
- `Gem::Specification.load("rails_mcp.gemspec").files` includes `lib/rails_mcp.rb`, `README.md`,
  `CHANGELOG.md`, `LICENSE.txt` and excludes `.claude/`, `.githooks/`, `test/`, `specs/`, `docs/`,
  `.github/`, `CLAUDE.md`, `REVIEW.md`, `.tool-versions`, `sig/`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`.
- The gemspec has no "tenant" string; metadata has `bug_tracker_uri` and
  `rubygems_mfa_required = "true"`.
- `sig/rails_mcp.rbs` and `sig/` are gone.
- The packaging test is green (and its VERSION↔CHANGELOG assertion passes once T2 lands).

**Note:** T1's VERSION↔CHANGELOG assertion (R4) depends on T2's dated `0.2.0` section. The test
file is written in T1; both must be green by the T5 gate. If run in isolation before T2, that one
assertion would fail — this is expected; the gate (T5) runs after T2.
**Tag:** `autonomous`.

### T2 — CHANGELOG: promote [Unreleased] to dated 0.2.0 + link refs
**Owns:**
- `CHANGELOG.md` (CHANGED: rename the `[Unreleased]` block to `## [0.2.0] - 2026-08-19`; regroup
  its entries under `### Added` / `### Changed` / `### Removed`; add a fresh empty
  `## [Unreleased]` above it; append compare link-reference definitions for `[Unreleased]`,
  `[0.2.0]`, `[0.1.0]`; leave `## [0.1.0] - 2026-08-12` unchanged)

**Depends on:** shipped. Independent of T1/T3/T4 (disjoint files).
**Acceptance (R3):** dated `0.2.0` section with Added/Changed/Removed groupings; fresh empty
`[Unreleased]`; compare link refs at the bottom; `0.1.0` section intact. (The T1 test asserts the
VERSION↔section match against this.)
**Tag:** `autonomous`.

### T3 — CI matrix + per-Rails gemfiles
**Owns:**
- `.github/workflows/main.yml` (CHANGED: matrix `ruby: ['3.2','3.3','3.4']` × a `gemfile` axis
  `[rails_7.1.gemfile, rails_7.2.gemfile, rails_8.0.gemfile]`; pass
  `BUNDLE_GEMFILE: gemfiles/${{ matrix.gemfile }}` to the `bundle exec rake` step; keep
  `persist-credentials: false` and `bundler-cache: true`)
- `gemfiles/rails_7.1.gemfile` (NEW: `eval_gemfile "../Gemfile"` then pin
  `gem "rails", "~> 7.1.0"` and matching `railties`/`activesupport`)
- `gemfiles/rails_7.2.gemfile` (NEW: same, `~> 7.2.0`)
- `gemfiles/rails_8.0.gemfile` (NEW: same, `~> 8.0.0`)

**Depends on:** shipped. Independent of T1/T2/T4 (disjoint files).
**Acceptance (R7):** matrix covers Ruby 3.2/3.3/3.4 (one entry aligns with `.tool-versions` 3.4)
and Rails 7.1/7.2/8.0; each gemfile evals the root `Gemfile` and pins its Rails line; the workflow
selects the gemfile via `BUNDLE_GEMFILE`.

**Note:** `gemfiles/` must not be packaged — it is excluded by the T1 allowlist (only `lib/` +
the three named runtime files ship). Add a `.lock` ignore for `gemfiles/*.lock` if the local
`.gitignore` does not already cover it (do NOT edit `docs/`/standards files).
**Tag:** `autonomous`.

### T4 — SECURITY.md, README links, CODE_OF_CONDUCT fix
**Owns:**
- `SECURITY.md` (NEW: private disclosure contact `brandon.casci@gmail.com`; supported versions
  `0.2.x`; response expectation; "do not open a public issue for a vulnerability")
- `README.md` (CHANGED: add "Security" and "Code of Conduct" links — `./SECURITY.md` and
  `./CODE_OF_CONDUCT.md`; no other content change)
- `CODE_OF_CONDUCT.md` (CHANGED: strip literal quotes around `rails_mcp` and "collaborative
  space"; fix the contact to `[brandon.casci@gmail.com](mailto:brandon.casci@gmail.com)` with no
  quotes inside the URL)

**Depends on:** shipped. Independent of T1/T2/T3 (disjoint files).
**Acceptance (R9, R10):** `SECURITY.md` exists with a private disclosure path and supported
versions; README links both community-health docs; `CODE_OF_CONDUCT.md` has no literal-quote
artifacts and no `mailto:"` substring. Neither `SECURITY.md` nor `CODE_OF_CONDUCT.md` is packaged
(guarded by the T1 allowlist + packaging test).
**Tag:** `autonomous`.

---

## Layer 1 — Gate

### T5 — Full gate
**Owns:** no new files — runs the gate and the spec's own checks.
**Depends on:** T1, T2, T3, T4.
**Acceptance (R11 + all):**
- `bundle exec rake` (minitest + standardrb) is green, including `test/packaging_test.rb`.
- `Gem::Specification.load("rails_mcp.gemspec").files` matches R1 (includes runtime files,
  excludes all internal paths).
- `grep -R "tenant" rails_mcp.gemspec` returns nothing.
- `CHANGELOG.md` has a `## [0.2.0] - 2026-08-19` section and compare link refs; `[Unreleased]` is
  empty.
- `.github/workflows/main.yml` matrix covers Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0.
- `sig/` is gone; `SECURITY.md` exists and is linked from README; `CODE_OF_CONDUCT.md` has no
  `mailto:"` substring.
- No gem runtime behavior changed (no `lib/` runtime path added or altered beyond the gemspec).
**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0009)
T1 ┐
T2 ┤
T3 ┼─→ T5
T4 ┘
```

T1–T4 parallel (disjoint files). T1 writes `test/packaging_test.rb`; its VERSION↔CHANGELOG
assertion is satisfied by T2's dated section — both are green by T5. T5 gates.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- `spec.files` is an explicit allowlist: `Dir.glob("lib/**/*") + %w[README.md CHANGELOG.md
  LICENSE.txt]` (existing files only); never a denylist.
- Release date for `0.2.0` is `2026-08-19` (spec-0009 completion date).
- `sig/` is removed, not populated (real RBS deferred).
- CI Rails matrix uses per-Rails `gemfiles/` selected via `BUNDLE_GEMFILE` (no Appraisal
  dependency); Ruby axis is 3.2/3.3/3.4 with one entry aligned to `.tool-versions`.
- `SECURITY.md` and `CODE_OF_CONDUCT.md` stay in-repo and are NOT packaged.
- All `standards_amendment` text from the assigned findings is tracked in spec 0015; this spec
  edits no standards docs.

No open decisions remain — every task is `autonomous`.
