# rails_mcp

Expose a hand-picked allow-list of Rails app actions to an AI client over MCP
(Model Context Protocol), on top of the official [`mcp`](https://rubygems.org/gems/mcp)
gem. `rails_mcp` ships the tool DSL and two seams — `authorize` (fail-closed) and a
per-call `ActiveSupport::Notifications` audit event; each app owns authorization, audit,
and identity. A safer replacement for raw `rails console`/`runner`
access: allow-list + attribution + audit.

v1 is read-only: it can register and invoke read-only diagnostic tools only. Protocol
plumbing (JSON-RPC, the Rack transport, tool schemas, annotations) is delegated to the
official `mcp` gem — none of it is reimplemented here.

## Installation

Add to your Gemfile:

```ruby
gem "rails_mcp"
```

Then run the install generator:

```bash
bundle install
rails g rails_mcp:install
```

This stamps, all app-owned and editable: a fail-closed `ApplicationMcpTool`, a
fail-closed `McpController` in front of the `/mcp` endpoint, the `/mcp` route to that
controller, an initializer, one read-only example tool, and example tests.

### Secure the `/mcp` endpoint (required)

The generated `app/controllers/mcp_controller.rb` is where the HTTP request is
authenticated before any tool runs. It is **fail-closed by default**: as stamped, its
`authenticate_acting_user!` seam raises, so `/mcp` denies **every** request until you
wire your app's real authentication there (Devise, a session, a bearer token — whatever
`ApplicationController` provides). A fresh install is unauthenticated until you secure it;
the default denies rather than exposes.

This is a second seam alongside the tool `authorize` check: `McpController` resolves *who*
the acting staff user is; `authorize` decides *what* that user may do. See
[`docs/USAGE.md`](docs/USAGE.md) for the full flow.

## Usage

- [`docs/USAGE.md`](docs/USAGE.md) — install, wire the two seams, the args DSL, writing a
  read-only tool, registering the allow-list, the app-owned controller and its customization
  seams, and testing.
- [`docs/SEAMS.md`](docs/SEAMS.md) — the frozen contracts: `authorize` (fail-closed) and the
  `invoke.rails_mcp` audit payload.

## Development

After checking out the repo, run `bin/setup` to install dependencies, then `rake test`.
`rake` runs the test suite and standardrb. The pre-commit hook runs the same gate plus the
ADR-constraint greps; do not bypass it.

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).
