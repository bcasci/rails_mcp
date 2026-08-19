## [Unreleased]

- Removed `RailsMcp::Registry` (`RailsMcp.registry`, `register`, `registered?`, `tools`,
  `clear`, `ToolNameCollision`) and the `expose!` macro. The app now owns the tool list: the
  install generator stamps `app/mcp/registered_tools.rb`, a `RegisteredTools` module whose
  `.all` returns an explicit array of tool classes, and the generated `McpController` passes
  `tools: RegisteredTools.all` to `MCP::Server.new`, resolved per request (spec 0009,
  ADR-0013, superseding ADR-0009).
- The allow-list guarantee is unchanged — it is the `mcp` gem's. A duplicate `tool_name` is
  caught by `mcp`'s `ToolNotUnique` at `MCP::Server.new`. The per-request list is reload-safe
  by construction; no ADR-0009 keying/collision machinery.
- Breaking public-seam change with no consumers, so no deprecation cycle; version 0.1.0 →
  0.2.0 (semver 0.x breaking = minor).
- Stripped multi-tenancy from the gem; tenancy is now host-app business logic (spec 0006,
  ADR-0010).
- Removed the bundled `dummy_app`; integration tests run against the verbatim template
  fixture under `test/integration/fixture_app/`.
- Corrected the docs' seam and route references to match the shipped code (the two seams
  `authorize` / `invoke.rails_mcp`, and the `POST /mcp` → `mcp#handle` route).
- Added the Getting-started recipe: install to a proven `tools/call`, with the token setup,
  the runnable JSON-RPC handshake, and the client-auth reality note (spec 0007).

## [0.1.0] - 2026-08-12

- Initial release
