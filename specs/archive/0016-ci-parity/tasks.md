# TASKS — CI parity with the litestream-ruby standard

Completed Thu Aug 20 01:04:54 EDT 2026 at commit 5beb62d

Task breakdown for spec 0016. Each task owns a DISJOINT set of edits. This spec touches only
`.github/workflows/main.yml` (and, only if strictly needed, an already-present build task) — it does
not touch `lib/`. References like `R1` point to this spec's `spec.md`.

T1 and T2 both edit `.github/workflows/main.yml` but DISJOINT regions: T1 adds the top-level
`concurrency` block; T2 adds a new `gem-smoke` job. They are sequenced (T1 → T2) only because they
edit the same file, not because of a logical dependency. T3 is the gate and depends on both.

---

## Layer 0 — Workflow edits (sequential on one file, disjoint regions)

### T1 — Cancel superseded CI runs (concurrency) — DONE
**Owns:**
- `.github/workflows/main.yml` (CHANGED: add a top-level `concurrency` block only — no change to
  `jobs.build`)

**Do:**
- Add, at the top level (a sibling of `on:` and `jobs:`):
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
  ```
- Leave `on:` (push to `main`, `pull_request`) and the whole `build` job unchanged.

**Depends on:** nothing.
**Acceptance (R1, R5):** `main.yml` has the top-level `concurrency` block with the exact
`group`/`cancel-in-progress` above; YAML still parses; `build` job untouched. Rationale is
litestream `gem-install.yml:2-4`.
**Tag:** `autonomous`.

### T2 — Build + install + load smoke job (`gem-smoke`) — DONE
**Owns:**
- `.github/workflows/main.yml` (CHANGED: add a new `jobs.gem-smoke` job only — no change to
  `jobs.build` or the `concurrency` block from T1)
- `Rakefile` (ONLY IF NEEDED per spec DECIDED: the smoke uses `gem build rails_mcp.gemspec`
  directly, so the Rakefile should NOT need editing; if a build task is used instead, keep the
  default task `test standard adr:check` unchanged)

**Do:**
- Add a standalone job `gem-smoke` (NOT a leg of the `build` matrix), `runs-on: ubuntu-latest`,
  Ruby `3.4` via `ruby/setup-ruby@v1`. Steps:
  1. `actions/checkout@v4` (with `persist-credentials: false`, matching the `build` job).
  2. Build the gem from the checked-out tree: `gem build rails_mcp.gemspec`.
  3. Install the built `.gem` into a throwaway dir independent of the bundle, e.g.:
     ```yaml
     - run: |
         gem build rails_mcp.gemspec
         gem install --install-dir "$RUNNER_TEMP/gems" ./rails_mcp-*.gem
         GEM_HOME="$RUNNER_TEMP/gems" GEM_PATH="$RUNNER_TEMP/gems" ruby -e 'require "rails_mcp"'
     ```
  4. The job fails if build, install, or `require` fails.
- Do NOT add per-platform gems, `rake download`, or any binary-execution step (rails_mcp ships no
  binary — spec Non-goals; litestream `gem-install.yml:22`, `rakelib/package.rake`).
- Do NOT add `bundler-cache`/`bundle install` for this job — the point is to test the installed
  package, not the working-tree bundle (R2).

**Depends on:** T1 (same file; add the job after the concurrency block lands to avoid a conflict).
**Acceptance (R2, R3, R5):** `gem-smoke` exists as a standalone single-Ruby job; it builds, installs
the built `.gem` off-bundle, and `require "rails_mcp"` from the installed gem; it is not a matrix
leg; YAML parses. Rationale: litestream's build+install+load shape — build in its `package` job
(`gem-install.yml:32`), install+run in `vanilla-install` (`:50-51`) — collapsed here into one job
(pure-Ruby single gem), with `require` as the pure-Ruby substitute for litestream's binary smoke (`:51`).
**Tag:** `autonomous`.

---

## Layer 1 — Gate (depends on T1, T2)

### T3 — Verify, no-regression, gate — DONE
**Owns:**
- (verification only — no new owned files beyond confirming T1/T2 edits)

**Do / Acceptance (R1–R5):**
- **R5 local reproduction:** from a clean checkout run
  `gem build rails_mcp.gemspec` → `gem install --install-dir "$(mktemp -d)" ./rails_mcp-*.gem` →
  `GEM_HOME=<that dir> GEM_PATH=<that dir> ruby -e 'require "rails_mcp"'`; confirm exit 0 (proves the
  `spec.files` allowlist ships a loadable package on the current tree). Clean up the built `.gem`.
- **YAML validity:** parse `.github/workflows/main.yml` (e.g.
  `ruby -ryaml -e 'YAML.load_file(".github/workflows/main.yml")'`); confirm `concurrency`,
  `jobs.build`, and `jobs.gem-smoke` are all present.
- **R4 no-regression:** confirm the `build` job still has the `3.2`/`3.3`/`3.4` ×
  `rails_7.1`/`rails_7.2`/`rails_8.0` matrix, `fail-fast: false`, `bundler-cache: true`, the
  `BUNDLE_GEMFILE` wiring, the isolation step, and `bundle exec rake`; confirm `gemfiles/`,
  `tasks/adr_check.rake`, and the Rakefile default task (`test standard adr:check`) are unchanged.
- **Gate:** run the repo pre-commit gate / `bundle exec rake` on the default Gemfile — green
  (this spec changes no Ruby, so the suite must be unaffected).

**Depends on:** T1, T2.
**Tag:** `autonomous`.

---

## Notes

- **Excluded on purpose** (spec Background / Non-goals): native per-platform gems and the
  binary-version smoke (litestream `gem-install.yml:22`, `:66-67`; `rakelib/package.rake`) — rails_mcp
  is pure-Ruby; and ruby-head / edge-Rails with `allow-failure` — litestream has no such leg to cite.
- rails_mcp is already ahead of litestream on Ruby 3.4, the Rails matrix, per-Rails gemfiles, and the
  isolation step; this spec adds only the two genuinely-missing litestream practices.
