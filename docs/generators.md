# Rails install generator — reference for T6

`rails g rails_mcp:install` follows the Devise `devise:install` pattern. This is the
non-obvious Rails-generator knowledge the T6 agent needs; general Ruby is assumed.

## Structure

- `lib/generators/rails_mcp/install/install_generator.rb` — the generator class:
  `class InstallGenerator < Rails::Generators::Base`.
- `source_root File.expand_path("templates", __dir__)`.
- Templates are `*.tt` (ERB) rendered with `template "x.tt", "dest/path"`.

## What it stamps (SPEC R7/R8)

- `app/mcp/application_mcp_tool.rb` — from `application_mcp_tool.rb.tt`: fail-closed, with
  clearly commented `authorize` and audit seams. **No tenant presumption** — not every app
  is multi-tenant (SPEC R11); any scoping is a commented, optional note.
- `config/initializers/rails_mcp.rb` — from `initializer.rb.tt`.
- one read-only example tool — from `example_read_only_tool.rb.tt`.
- example tests (authz denial, audit-row-written) — from `example_tests.rb.tt`.
- the `/mcp` route line — injected into `config/routes.rb`.

## Route injection (idempotent)

- Use `route "mount_mcp '/mcp'"`, or `inject_into_file "config/routes.rb"` guarded by a
  check for the existing mount so a second run does not duplicate the line.

## Idempotency

- Safe to re-run: `template` prompts on conflict; guard the route injection; never clobber
  an edited `ApplicationMcpTool` — it is app-owned after the first run.

## Testing the generator

- `Rails::Generators::TestCase`, `tests InstallGenerator`, a tmp `destination`,
  `setup { prepare_destination }`.
- `run_generator`, then `assert_file` on each stamped file and
  `assert_file "config/routes.rb", /mount_mcp/`.
