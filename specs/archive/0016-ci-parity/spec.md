# SPEC — CI parity with the litestream-ruby standard

Build contract for spec 0016: close the gap between rails_mcp's CI (`.github/workflows/main.yml`,
after spec 0010) and the CI practices demonstrated by the mature public gem litestream-ruby, adding
only the transferable practices litestream has that rails_mcp lacks. Given/When/Then acceptance
criteria; `DECIDED` marks settled choices.

In force: ADR-0001 / ADR-0004 (no hand-rolled transport; no gem-side policy) — unchanged by this
spec, which touches only CI and Rake wiring, not `lib/`.

---

## Background

rails_mcp spec 0010 (`specs/archive/0010-packaging-release-hygiene`) already gave CI a
Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0 matrix, per-Rails gemfiles (`gemfiles/rails_*.gemfile`,
selected via `BUNDLE_GEMFILE`), `bundler-cache: true`, an "each test file in isolation" step, and a
shared `rake adr:check` folded into the default task. On the axes litestream tests, rails_mcp is
already **ahead**: litestream's matrix is Ruby `3.2`/`3.3` only with a single Gemfile and no Rails
matrix (`litestream-ruby/.github/workflows/main.yml:14-18`).

What litestream still does that rails_mcp does **not**:

1. **Cancel superseded runs.** litestream sets a `concurrency` group with
   `cancel-in-progress: true` so a new push to a branch/PR cancels the in-flight run
   (`litestream-ruby/.github/workflows/gem-install.yml:2-4`). rails_mcp's `main.yml` has no
   `concurrency` block, so stacked pushes run to completion and waste runner minutes.
2. **Build the gem and smoke-install it.** litestream proves the packaged gem installs across two
   coupled jobs: a `package` job builds the platform `.gem` (`gem-install.yml:32`,
   `bundle exec rake gem:<platform>`), and a `vanilla-install` job then `needs:` it, downloads the
   artifact, `gem install`s it (`gem-install.yml:50`), and runs the installed artifact
   (`gem-install.yml:51`, a **binary-execution** smoke — `litestream 2>&1 | fgrep ...`). rails_mcp
   takes only the **transferable shape — build + install + load** — and realizes it differently:
   because it is a single pure-Ruby `.gem` with no cross-platform artifact, it **collapses build +
   install + load into one job** (no `needs:`/artifact handoff), and, since litestream has **no**
   `require`-based load smoke (it load-checks by running the Go binary, `gem-install.yml:51`), the
   `require "rails_mcp"` load-check is the **pure-Ruby substitute** for that binary smoke — not a
   line-for-line port. rails_mcp's CI today only runs `bundle exec rake` against the working tree;
   it never proves the built package (the `spec.files` allowlist added in spec 0010) actually
   installs and `require`s.

### Explicitly excluded from parity (litestream practice rails_mcp must NOT copy)

- **Native cross-platform gem packaging and real-binary integration.** litestream's entire
  `gem-install.yml` matrix over `["ruby","x86_64-darwin","arm64-darwin","x86_64-linux",...]`
  (`gem-install.yml:22`), the `rake gem:<platform>` tasks and `rake download`
  (`litestream-ruby/rakelib/package.rake`), and the "run the `litestream` binary and grep its
  version" smoke (`gem-install.yml:66-67`, `:105-107`) exist only because litestream wraps a
  precompiled Go binary. rails_mcp is a pure-Ruby gem with no native extension and no bundled
  executable; per-platform gems and a binary-execution smoke are irrelevant. Only the
  **build + install + load** shape is transferable, reduced to the single `ruby` platform.
- **ruby-head / edge-Rails with `allow-failure`.** litestream does **not** run a head-Ruby or
  edge-Rails leg (no `head`, `continue-on-error`, or `nightly` anywhere under
  `litestream-ruby/.github/`). There is no litestream precedent to cite, so this spec does not add
  one — it stays strictly within demonstrated parity.

---

## Scope

### In this spec

- Add a `concurrency` block to `.github/workflows/main.yml` that cancels superseded in-flight runs
  per ref.
- Add a gem build-and-install smoke: build the packaged `.gem` from the checked-out tree,
  `gem install` it into a clean location, and `require "rails_mcp"` from the installed gem to prove
  the `spec.files` allowlist ships a loadable package.
- Keep the existing matrix, gemfiles, `bundler-cache`, isolation step, and `rake adr:check`
  untouched.

### Out of scope

- Any change to `lib/`, the gemspec's `spec.files` allowlist, or the Rails/Ruby matrix axes
  (already ahead of litestream).
- Native/per-platform gems, `rake download`, binary-execution smoke (excluded above).
- ruby-head / edge-Rails legs (no litestream precedent; excluded above).
- A release/publish workflow (not part of litestream's CI parity; deferred).

**DECIDED** the concurrency group is
`group: ${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true`, mirroring
litestream's `gem-install.yml:2-4` (`${{github.workflow}}-${{github.ref}}`), scoped so main-branch
pushes and each PR cancel only their own superseded runs.

**DECIDED** the smoke is a **separate job** named `gem-smoke` (not folded into the matrix), single
Ruby (`3.4`, the repo's `.tool-versions` pin) and single default Gemfile, because the package
contents are matrix-independent (the `.gem` is one artifact) — running it once mirrors litestream
running `vanilla-install` once, not per matrix cell (`gem-install.yml:39-45`).

**DECIDED** the smoke builds with `gem build rails_mcp.gemspec` and installs into a throwaway dir
via `gem install --install-dir` (or `GEM_HOME` to a temp path) so it does not depend on the bundle,
then loads with `ruby -e 'require "rails_mcp"'` under that dir — the pure-Ruby analog of
litestream's `gem install pkg/*.gem` + run (`gem-install.yml:50-51`). No binary is executed
(rails_mcp ships none).

**DECIDED** no Rakefile change is required if `gem build rails_mcp.gemspec` from the repo root
produces the package; a `rake build`/`bundler/gem_tasks` task already exists (Rakefile
`require "bundler/gem_tasks"`). The spec uses whichever the task chooses, provided the built file is
locatable for `gem install`.

---

## Requirements

### R1 — Superseded CI runs are cancelled (concurrency)

- **Given** `.github/workflows/main.yml`, **when** read, **then** it declares a top-level
  `concurrency` block with `group: ${{ github.workflow }}-${{ github.ref }}` and
  `cancel-in-progress: true`.
- **Given** two pushes to the same ref in quick succession, **when** the second starts, **then** the
  first in-flight run is cancelled (the concurrency group serializes per ref).
- **Rationale:** litestream `.github/workflows/gem-install.yml:2-4` sets this group +
  `cancel-in-progress: true` (litestream quotes the string, `"${{github.workflow}}-${{github.ref}}"`;
  the `${{ ... }}` whitespace/quoting is GitHub-equivalent, so this is the same group, not a
  byte-identical copy); rails_mcp's `main.yml` currently has no `concurrency` block.

### R2 — The built gem installs and loads (build + install smoke)

- **Given** `.github/workflows/main.yml`, **when** read, **then** there is a job (`gem-smoke`) that,
  on a clean checkout, (a) builds the gem from `rails_mcp.gemspec`, (b) `gem install`s the resulting
  `.gem` into a location independent of the project bundle, and (c) runs
  `ruby -e 'require "rails_mcp"'` resolving `rails_mcp` from the **installed** gem, and the job
  fails if any step fails.
- **Given** the smoke job, **when** it installs, **then** it installs the just-built `.gem` file (a
  path/glob to the built artifact), not `bundle install` of the working tree — so it exercises the
  `spec.files` allowlist, not the repo.
- **Given** the smoke job, **when** the `require` runs, **then** it exits 0 (the packaged file list
  is sufficient to load `RailsMcp`); a missing runtime file in `spec.files` makes it exit non-zero.
- **Rationale:** litestream proves a packaged gem installs by building it in a `package` job
  (`gem-install.yml:32`) and, in a separate `vanilla-install` job, `gem install`ing the downloaded
  artifact (`:50`) and running it (`:51`, a binary-execution smoke). rails_mcp adopts the
  build+install+load *shape* in one job (single pure-Ruby gem, no cross-job artifact) and load-checks
  with `require` as the pure-Ruby substitute for litestream's binary smoke; rails_mcp's CI otherwise
  never proves its packaged gem installs/loads.

### R3 — Smoke runs once, single Ruby, off the matrix

- **Given** the `gem-smoke` job, **when** read, **then** it is a standalone job (not a leg of the
  Ruby × Gemfile `build` matrix), pinned to Ruby `3.4` and the repo default Gemfile.
- **Given** the workflow, **when** it runs, **then** `gem-smoke` and the `build` matrix run in the
  same workflow (both on push-to-main and pull_request), and neither depends on the other (no
  `needs:` coupling that would let a matrix flake block the smoke or vice-versa) — unless a
  `needs:`/artifact handoff is chosen; if so, it is stated in the job and does not change what R2
  verifies.
- **Rationale:** litestream runs `vanilla-install` as one job, not per matrix cell
  (`gem-install.yml:39-45`); package contents are matrix-independent.

### R4 — Nothing already-ahead is regressed

- **Given** `.github/workflows/main.yml` after this spec, **when** read, **then** the existing
  `build` job still has the Ruby `3.2`/`3.3`/`3.4` × `rails_7.1`/`rails_7.2`/`rails_8.0` matrix,
  `fail-fast: false`, `bundler-cache: true`, the `BUNDLE_GEMFILE: gemfiles/${{ matrix.gemfile }}`
  wiring, the "Each test file passes in isolation" step, and `bundle exec rake` (which includes
  `adr:check`) — all unchanged.
- **Given** `gemfiles/`, `Rakefile`, and `tasks/adr_check.rake`, **when** read, **then** they are
  unchanged by this spec (or, if the Rakefile is touched, only to expose a build task the smoke
  uses, per the DECIDED note — with the default task still `test standard adr:check`).

### R5 — Workflow is valid and the smoke is locally reproducible

- **Given** `.github/workflows/main.yml`, **when** parsed as YAML, **then** it is valid (no syntax
  errors; `concurrency`, `jobs.build`, and `jobs.gem-smoke` all present).
- **Given** the smoke steps, **when** the same commands are run locally from a clean checkout
  (`gem build rails_mcp.gemspec` → `gem install --install-dir <tmp> <built>.gem` →
  `GEM_HOME=<tmp> GEM_PATH=<tmp> ruby -e 'require "rails_mcp"'`), **then** they succeed on the
  current tree — proving the criteria are checkable without pushing to CI.

---

## Non-goals (guardrails)

- No native/per-platform gems, `rake gem:<platform>`, `rake download`, or binary-execution smoke —
  rails_mcp ships no binary (excluded; litestream `gem-install.yml:22`, `rakelib/package.rake`).
- No ruby-head or edge-Rails leg — no litestream precedent to cite (excluded).
- No change to `lib/`, the `spec.files` allowlist, or the matrix axes.
- No new release/publish workflow.
- No change to ADR-0001/ADR-0004 constraints or the `adr:check` gate.
