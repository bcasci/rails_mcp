## [Unreleased]

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
