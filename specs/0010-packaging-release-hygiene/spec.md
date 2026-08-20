# SPEC — Packaging, CI & release metadata

> **Build order: 2 of 6.** Recommended sequence: 0015 → 0010 → 0011 → 0013 → 0014 → 0012. Depends on: 0015. GitHub does not enforce spec order — see the release tracking issue.

Build contract for spec 0010: make the built gem and its release/CI metadata trustworthy and
minimal. Today the gem packages 44 internal files (the whole AI-build apparatus and security
control catalog), its CHANGELOG and version disagree, CI tests one Ruby against one Rails while
the gemspec advertises a range, the description names a capability that was removed, required
RubyGems metadata is missing, `sig/` is a default stub, and the community-health docs are absent
or malformed. This spec fixes the packaging, CI, and community-health surface — code/tests/docs
only.

Builds on shipped specs 0001–0009 (archived). Given/When/Then acceptance criteria; `DECIDED`
marks settled choices.

Governing decisions in force: ADR-0010 (tenancy stripped), ADR-0013 (app-owned tool list),
ADR-0003 (read-only v1). No new ADR is created here.

---

## Background

`rails_mcp` is a security-adjacent public gem: it exposes a hand-picked allow-list of Rails app
actions to an AI client. Two properties matter for its package:

1. **The built gem must ship runtime paths only.** The current gemspec `spec.files` is a
   *denylist* (`git ls-files` then reject a handful of paths), so everything not explicitly
   rejected ships — including `.claude/`, `CLAUDE.md`, `REVIEW.md`, `.githooks/pre-commit`, all
   ADRs, and every archived spec. For a security-adjacent gem this leaks the control catalog and
   its gaps to every installer.
2. **Release metadata must be internally consistent and complete.** `version.rb` says `0.2.0`
   while the CHANGELOG still files those changes under `[Unreleased]`; the description still
   advertises "tenant scoping" after ADR-0010 removed tenancy; CI tests only Ruby 3.2.0; required
   RubyGems metadata (`rubygems_mfa_required`, `bug_tracker_uri`) is missing; `sig/` is a bundler
   stub typing only `VERSION`; and there is no `SECURITY.md`, with an unlinked, malformed
   `CODE_OF_CONDUCT.md`.

This spec makes each of those checkable and adds tests/CI checks so they cannot silently
regress.

---

## Scope

### In this spec

- Invert `spec.files` to an explicit allowlist of runtime paths; add a packaging test that fails
  if any internal path appears in the packaged file list. (PKG-01)
- Promote the CHANGELOG `[Unreleased]` block to a dated `## [0.2.0] - 2026-08-19` section with
  Added/Changed/Removed groupings and compare link references, plus a fresh empty `[Unreleased]`;
  add a test asserting `VERSION` has a matching dated CHANGELOG section. (PKG-02)
- Expand the CI matrix to Ruby 3.2/3.3/3.4 and Rails 7.1/7.2/8.0, aligning one entry with
  `.tool-versions` (3.4.4). (CI-01)
- Correct the gemspec description: "tenant scoping" → "identity". (PKG-03)
- Add `rubygems_mfa_required = 'true'` and `bug_tracker_uri` to the gemspec metadata. (PKG-04)
- Delete `sig/` (the default RBS stub) and drop it from the package. (PKG-07)
- Add `SECURITY.md` (private disclosure path, supported versions, response expectations) and link
  it plus `CODE_OF_CONDUCT.md` from `README.md`; keep both in-repo but excluded from the package.
  (DOC-03)
- Fix the `CODE_OF_CONDUCT.md` literal-quote artifacts and the broken mailto link. (DOC-06)

### Out of scope

- Any change to gem runtime behavior — the invoke pipeline, the args/annotations DSL, the
  controller public-`mcp` pattern, identity on `server_context`, the fail-closed seams, the
  allow-list guarantee, arg-dropping, one-event, per-request identity, or read/write neutrality.
  This spec touches packaging, CI, and community-health docs only; no gem guarantee changes.
- Writing real RBS types (PKG-07 resolves by **dropping** `sig/`, not by authoring types).
- **Standards amendments.** Several findings (PKG-01, PKG-02, PKG-03, PKG-04, PKG-07, CI-01, and
  DOC-03's pre-publish checklist) carry `standards_amendment` text for `docs/conventions.md` /
  `CLAUDE.md`. Those are **tracked in spec 0015** (which owns all standards amendments). This spec
  does NOT edit `docs/conventions.md`, `CLAUDE.md`, `REVIEW.md`, or the `spec-driven-dev` skill.
- Enabling MFA on the RubyGems account (an out-of-band account action; this spec only sets the
  gemspec flag that requires it).

**DECIDED** the release date recorded for `0.2.0` is `2026-08-19` (the spec-0009 completion
date), matching the CHANGELOG dating convention.

**DECIDED** `sig/` is **removed**, not populated — real RBS + Steep/CI validation is deferred
until types exist; a stub advertising type support the gem does not have is worse than none
(PKG-07 resolution, first branch declined in favor of the delete branch).

**DECIDED** the packaging allowlist is `Dir.glob("lib/**/*")` plus the explicit runtime files
`README.md`, `CHANGELOG.md`, `LICENSE.txt`. `SECURITY.md` and `CODE_OF_CONDUCT.md` stay in-repo
and are NOT packaged (DOC-03).

**DECIDED** the CI Rails matrix is expressed with per-Rails Gemfiles under `gemfiles/` selected
via `BUNDLE_GEMFILE` (no new Appraisal dependency), keeping the existing single job green when
run locally with the root `Gemfile`.

---

## Requirements

### R1 — Gemspec `spec.files` is an explicit allowlist of runtime paths (PKG-01)

- **File(s) changed:** `rails_mcp.gemspec`.
- **Given** `rails_mcp.gemspec`, **when** read, **then** `spec.files` is built from an explicit
  allowlist — `Dir.glob("lib/**/*")` plus `%w[README.md CHANGELOG.md LICENSE.txt]` (restricted to
  files that exist) — and no longer uses `git ls-files` with a reject/denylist.
- **Given** the resolved `Gem::Specification.load("rails_mcp.gemspec").files`, **when** inspected,
  **then** it contains `lib/rails_mcp.rb`, `README.md`, `CHANGELOG.md`, and `LICENSE.txt`, and
  contains **no** path beginning with any of: `.claude/`, `.githooks/`, `test/`, `specs/`,
  `docs/`, `.github/`, and no `CLAUDE.md`, `REVIEW.md`, `.tool-versions`, `sig/`,
  `SECURITY.md`, or `CODE_OF_CONDUCT.md`.

### R2 — Packaging test guards the packaged file list (PKG-01)

- **File(s) changed:** `test/packaging_test.rb` (NEW).
- **Given** the test suite, **when** `bundle exec rake` runs, **then** a test loads the gemspec
  and asserts the packaged `spec.files` includes `lib/rails_mcp.rb`, `README.md`, `CHANGELOG.md`,
  `LICENSE.txt` and asserts it excludes every forbidden internal prefix/path listed in R1
  (`.claude/`, `.githooks/`, `test/`, `specs/`, `docs/`, `.github/`, `CLAUDE.md`, `REVIEW.md`,
  `.tool-versions`, `sig/`).
- **Given** a regression that re-adds an internal path to `spec.files`, **when** the suite runs,
  **then** this test fails (a checkable guard, not prose).

### R3 — CHANGELOG promotes `[Unreleased]` to a dated `0.2.0` section (PKG-02)

- **File(s) changed:** `CHANGELOG.md`.
- **Given** `CHANGELOG.md`, **when** read, **then** the former `[Unreleased]` content is under a
  dated `## [0.2.0] - 2026-08-19` heading, its entries grouped under `### Added`, `### Changed`,
  and `### Removed` sub-headings (Keep a Changelog), and there is a fresh empty `## [Unreleased]`
  section above it.
- **Given** the bottom of `CHANGELOG.md`, **when** read, **then** it contains compare
  link-reference definitions for `[Unreleased]`, `[0.2.0]`, and `[0.1.0]` pointing at the
  `github.com/bcasci/rails_mcp` compare/tag URLs.
- **Given** the existing `## [0.1.0] - 2026-08-12` section, **when** read, **then** it is
  preserved unchanged.

### R4 — Test asserts VERSION has a matching dated CHANGELOG section (PKG-02)

- **File(s) changed:** `test/packaging_test.rb` (same NEW file as R2).
- **Given** the suite, **when** it runs, **then** a test reads `RailsMcp::VERSION` and
  `CHANGELOG.md` and asserts a dated section header `## [<VERSION>] - <date>` exists (a section
  matching `/^## \[#{VERSION}\] - \d{4}-\d{2}-\d{2}$/`), and that the same version does **not**
  appear only under `[Unreleased]`.
- **Given** a future `VERSION` bump whose changes are still under `[Unreleased]`, **when** the
  suite runs, **then** this test fails.

### R5 — Gemspec description matches the current README (PKG-03)

- **File(s) changed:** `rails_mcp.gemspec`.
- **Given** `rails_mcp.gemspec`, **when** read, **then** the `spec.description` phrase
  "authorization, audit, and tenant scoping" is replaced with "authorization, audit, and
  identity", and the string "tenant" no longer appears anywhere in the gemspec.
- **Given** the description, **when** compared to `README.md`, **then** it names the same three
  app-owned concerns the README lists (authorization, audit, identity).

### R6 — Gemspec sets required RubyGems metadata (PKG-04)

- **File(s) changed:** `rails_mcp.gemspec`.
- **Given** `rails_mcp.gemspec`, **when** read, **then** `spec.metadata["rubygems_mfa_required"]`
  is `"true"` and `spec.metadata["bug_tracker_uri"]` is set to `"#{spec.homepage}/issues"`.
- **Given** `Gem::Specification.load("rails_mcp.gemspec").metadata`, **when** inspected in a test,
  **then** it contains keys `homepage_uri`, `source_code_uri`, `changelog_uri`,
  `bug_tracker_uri`, and `rubygems_mfa_required` set to `"true"`.
- **File(s) changed (test):** `test/packaging_test.rb` (same NEW file as R2) asserts the above
  metadata keys and values.

### R7 — CI tests the full declared support range (CI-01)

- **File(s) changed:** `.github/workflows/main.yml`; `gemfiles/rails_7.1.gemfile`,
  `gemfiles/rails_7.2.gemfile`, `gemfiles/rails_8.0.gemfile` (NEW).
- **Given** `.github/workflows/main.yml`, **when** read, **then** the matrix lists
  `ruby: ['3.2', '3.3', '3.4']` and a `gemfile` axis selecting the three `gemfiles/` entries via
  `BUNDLE_GEMFILE`, so every minor Ruby from `required_ruby_version` up to the dev Ruby is
  exercised and the min + latest Rails of the covered majors (7.1, 7.2, 8.0) are exercised.
- **Given** the matrix, **when** read, **then** at least one entry uses a Ruby that matches
  `.tool-versions` (3.4).
- **Given** each `gemfiles/*.gemfile`, **when** read, **then** it evals the root `Gemfile`
  (`eval_gemfile "../Gemfile"`) or requires the gemspec and pins `rails`/`railties`/
  `activesupport` to the stated Rails line (`~> 7.1.0`, `~> 7.2.0`, `~> 8.0.0` respectively).
- **Given** the workflow step, **when** read, **then** it passes `BUNDLE_GEMFILE:
  gemfiles/${{ matrix.gemfile }}` to `bundle exec rake`.

### R8 — Drop the default RBS stub from the tree and the package (PKG-07)

- **File(s) changed:** `sig/rails_mcp.rbs` (DELETE), `sig/` (DELETE if empty),
  `rails_mcp.gemspec` (already excludes it via the R1 allowlist).
- **Given** the repo tree, **when** listed, **then** `sig/rails_mcp.rbs` does not exist and the
  `sig/` directory is gone.
- **Given** the packaged `spec.files` (R1), **when** inspected, **then** no `sig/` path is
  present (covered by the R2 exclusion assertion).

### R9 — Add SECURITY.md and link community-health docs from README (DOC-03)

- **File(s) changed:** `SECURITY.md` (NEW), `README.md`.
- **Given** `SECURITY.md`, **when** read, **then** it states a private disclosure contact
  (`brandon.casci@gmail.com`), the supported versions (the current `0.2.x` line), and a response
  expectation, and instructs reporters not to open a public issue for a vulnerability.
- **Given** `README.md`, **when** read, **then** it links to `SECURITY.md` and to
  `CODE_OF_CONDUCT.md` (e.g. a "Security" and "Code of Conduct" mention with `./SECURITY.md` and
  `./CODE_OF_CONDUCT.md` relative links).
- **Given** the packaged `spec.files` (R1), **when** inspected, **then** neither `SECURITY.md` nor
  `CODE_OF_CONDUCT.md` is packaged (they stay in-repo only; covered by R2).

### R10 — Fix CODE_OF_CONDUCT quote artifacts and mailto (DOC-06)

- **File(s) changed:** `CODE_OF_CONDUCT.md`.
- **Given** `CODE_OF_CONDUCT.md`, **when** read, **then** the project name renders as plain
  `rails_mcp` (no literal quotes), "collaborative space" has no literal quotes, and the contact
  link is `[brandon.casci@gmail.com](mailto:brandon.casci@gmail.com)` with no quotes inside the
  URL.
- **Given** the file, **when** searched, **then** no `mailto:"` (quote-inside-URL) substring
  remains.

### R11 — No collateral behavior change; gate green

- **File(s) changed:** none beyond those named in R1–R10.
- **Given** the suite, **when** `bundle exec rake` (minitest + standardrb) runs, **then** it is
  green, and the gem's runtime behavior — invoke pipeline, args/annotations DSL, controller
  public-`mcp` pattern, identity on `server_context`, fail-closed seams, allow-list, arg-dropping,
  one-event, per-request identity, read/write neutrality — is unchanged (this spec adds no
  runtime code path).

---

## Non-goals (guardrails)

- No standards-doc edits: `docs/conventions.md`, `CLAUDE.md`, `REVIEW.md`, and the
  `spec-driven-dev` skill are NOT touched here — every `standards_amendment` from the assigned
  findings is tracked in spec 0015.
- No new ADR and no rewrite of an existing ADR body.
- No real RBS authoring — `sig/` is removed, not populated (deferred).
- No change to any gem runtime guarantee or public seam.
- No RubyGems account action (MFA is enabled out of band; this spec only sets the flag).

---

## Finding coverage

| Finding | Requirement(s) |
|---------|----------------|
| PKG-01  | R1, R2         |
| PKG-02  | R3, R4         |
| PKG-03  | R5             |
| PKG-04  | R6             |
| PKG-07  | R8             |
| CI-01   | R7             |
| DOC-03  | R9             |
| DOC-06  | R10            |
