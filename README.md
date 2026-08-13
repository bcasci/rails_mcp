# rails_mcp

Expose a hand-picked allow-list of Rails app actions to an AI client over MCP
(Model Context Protocol), on top of the official [`mcp`](https://rubygems.org/gems/mcp)
gem. `rails_mcp` ships the tool DSL and two seams — `authorize` (fail-closed) and a
per-call `ActiveSupport::Notifications` audit event; each app owns authorization, audit,
identity, and any tenant scoping. A safer replacement for raw `rails console`/`runner`
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

This stamps an app-owned, fail-closed `ApplicationMcpTool`, a `/mcp` mount, an
initializer, one read-only example tool, and example tests.

## Development

After checking out the repo, run `bin/setup` to install dependencies, then `rake test`.
`rake` runs the test suite and standardrb. The pre-commit hook runs the same gate plus the
ADR-constraint greps; do not bypass it.

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).
