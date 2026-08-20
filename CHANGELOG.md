## [Unreleased]

## [0.2.1] - 2026-08-20

Release-readiness hardening. No public API change (the `authorize` signature, the
`invoke.rails_mcp` payload, the args/annotations DSL, and the generator interface are all
unchanged); everything here is a fix, a security/packaging improvement, or CI/docs.

### Fixed

- Tools that set a raw `input_schema` (opting out of the `arg` DSL) no longer drop every
  argument before `perform` — the allow-list is the effective input schema, not the `arg`
  list (ARCH-02).
- The gem reads no `mcp` private internals: the "explicit schema" distinction is tracked in
  the gem's own state, guarded by a public-contract drift test (ARCH-01, ADR-0015).

### Security

- The generated bearer-auth recipe stores a token digest and compares in constant time
  instead of storing/looking up a plaintext token (SEC-01).
- The ADR / credential / dynamic-dispatch constraint greps run in CI via `rake adr:check`,
  not only the local pre-commit hook (SEC-04, SEC-05).

### Changed

- Gemspec `spec.files` is an explicit allowlist — the built `.gem` ships only runtime files
  (`lib/`, README, CHANGELOG, LICENSE), not the development apparatus (PKG-01).
- Corrected doc claims to match shipped behavior: the stateless first-call (no `initialize`
  handshake), the audit-event scope, and stale ADR statuses (spec 0012).

### Added

- CI matrix: Ruby 3.2 / 3.3 / 3.4 × Rails 7.1 / 7.2 / 8.0, each test file run in isolation,
  a packaged-gem build → install → `require` smoke, and run-cancelling concurrency
  (specs 0010, 0016).

## [0.2.0] - 2026-08-19

### Added

- Added the Getting-started recipe: install to a proven `tools/call`, with the token setup,
  the runnable JSON-RPC handshake, and the client-auth reality note (spec 0007).

### Changed

- Corrected the docs' seam and route references to match the shipped code (the two seams
  `authorize` / `invoke.rails_mcp`, and the `POST /mcp` → `mcp#handle` route).
- The allow-list guarantee is unchanged — it is the `mcp` gem's. A duplicate `tool_name` is
  caught by `mcp`'s `ToolNotUnique` at `MCP::Server.new`. The per-request list is reload-safe
  by construction; no ADR-0009 keying/collision machinery.
- Breaking public-seam change with no consumers, so no deprecation cycle; version 0.1.0 →
  0.2.0 (semver 0.x breaking = minor).

### Removed

- Removed `RailsMcp::Registry` (`RailsMcp.registry`, `register`, `registered?`, `tools`,
  `clear`, `ToolNameCollision`) and the `expose!` macro. The app now owns the tool list: the
  install generator stamps `app/mcp/registered_tools.rb`, a `RegisteredTools` module whose
  `.all` returns an explicit array of tool classes, and the generated `McpController` passes
  `tools: RegisteredTools.all` to `MCP::Server.new`, resolved per request (spec 0009,
  ADR-0013, superseding ADR-0009).
- Stripped multi-tenancy from the gem; tenancy is now host-app business logic (spec 0006,
  ADR-0010).
- Removed the bundled `dummy_app`; integration tests run against the verbatim template
  fixture under `test/integration/fixture_app/`.

## [0.1.0] - 2026-08-12

- Initial release

[Unreleased]: https://github.com/bcasci/rails_mcp/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bcasci/rails_mcp/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/bcasci/rails_mcp/releases/tag/v0.1.0
