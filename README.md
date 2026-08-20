# rails_mcp

Expose a hand-picked allow-list of Rails app actions to an AI client over MCP
(Model Context Protocol), on top of the official [`mcp`](https://rubygems.org/gems/mcp)
gem. `rails_mcp` ships the tool DSL and two seams — `authorize` (fail-closed) and a
per-call `ActiveSupport::Notifications` audit event; each app owns authorization, audit,
and identity. A safer replacement for raw `rails console`/`runner`
access: allow-list + attribution + audit.

The gem is a neutral MCP tool-exposure conduit (ADR-0012): it invokes whatever tools the app
lists (in its app-owned `RegisteredTools`) — read or write, the app decides. It imposes no read/write,
identity, permission, audience, or persistence policy of its own; those are app decisions in
the tool, controller, and app code. `read_only!` remains available as an optional advisory
annotation. Protocol plumbing (JSON-RPC, the Rack transport, tool schemas, annotations) is
delegated to the official `mcp` gem — none of it is reimplemented here.

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
controller, an initializer, `app/mcp/registered_tools.rb` (the app-owned list of tools the
AI may call), one read-only example tool, and example tests.

### Secure the `/mcp` endpoint (required)

The generated `app/controllers/mcp_controller.rb` is where the HTTP request is
authenticated before any tool runs. It is **fail-closed by default**: as stamped, its
`authenticate_acting_user!` seam raises, so `/mcp` denies **every** request until you
wire your app's real authentication there (Devise, a session, a bearer token — whatever
`ApplicationController` provides). A fresh install is unauthenticated until you secure it;
the default denies rather than exposes.

This is a second seam alongside the tool `authorize` check: `McpController` resolves *who*
the acting user is (whatever identity your app resolves); `authorize` decides *what* that
user may do. See
[`docs/USAGE.md`](docs/USAGE.md) for the full flow.

## Make your first call

From install to a proven `tools/call`. v1 auth is a **static `Authorization: Bearer` token
over Streamable HTTP** — prove it with `curl` or an MCP inspector that sets a custom header.
Claude's hosted remote-MCP connector expects OAuth 2.1, so a static Bearer is not guaranteed
to connect from that surface. Full recipe (the `api_token_digest` migration, the user seed, the
resolving scope) is in [`docs/USAGE.md`](docs/USAGE.md#2a-make-your-first-call-install--a-proven-toolscall).

1. **Install** — add the gem (a git line until it is published) and generate:

   ```ruby
   # Gemfile
   gem "rails_mcp", git: "https://github.com/your-org/rails_mcp.git"
   ```

   ```bash
   bundle install
   rails g rails_mcp:install
   ```

2. **Wire auth** — in `app/controllers/mcp_controller.rb`, replace the fail-closed
   `authenticate_acting_user!` with the stamped bearer example, and override `authorize` in
   `app/mcp/application_mcp_tool.rb` to permit the acting user your app resolves (both deny
   until you do):

   ```ruby
   def authenticate_acting_user!
     # Anchored scheme parse — requires the `Bearer ` prefix; never a global strip.
     token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
     # Digest at rest: look up by SHA-256 digest, never a raw `api_token` column.
     user = User.find_by(api_token_digest: Digest::SHA256.hexdigest(token)) if token
     user || raise(RailsMcp::NotAuthorized)
   end
   ```

3. **Call it** — the generator seeds `ExampleReadOnlyTool` in `RegisteredTools.all`
   (`app/mcp/registered_tools.rb`), so it is already on the allow-list. Run the handshake
   against `POST /mcp` (`mcp#handle`) and finish with a `tools/call`:

   ```bash
   curl -sS http://localhost:3000/mcp \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -H "Accept: application/json, text/event-stream" \
     -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"example_read_only","arguments":{"subject":"first call"}}}'
   # => {"result":{"content":[{"type":"text","text":"Looked up: first call"}],"isError":false}}
   # If this returns a "not initialized" error, send an `initialize` request first (see USAGE §2a).
   ```

## Usage

- [`docs/USAGE.md`](docs/USAGE.md) — install, wire the two seams, the args DSL, writing a
  read-only tool, the app-owned `RegisteredTools` list (the allow-list), the app-owned
  controller and its customization seams, and testing.
- [`docs/SEAMS.md`](docs/SEAMS.md) — the frozen contracts: `authorize` (fail-closed) and the
  `invoke.rails_mcp` audit payload.

## Development

After checking out the repo, run `bin/setup` to install dependencies, then `rake test`.
`rake` runs the test suite and standardrb. The pre-commit hook runs the same gate plus the
ADR-constraint greps; do not bypass it.

## Security

Please report vulnerabilities privately — see [`SECURITY.md`](./SECURITY.md). Do not open a
public issue for a vulnerability.

## Code of Conduct

Participation in this project is governed by the [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).
