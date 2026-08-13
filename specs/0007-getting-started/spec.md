# SPEC — Getting started: install to first `/mcp` call

Build contract for spec 0007: add the copy-paste recipe that takes a host app from install to a
proven `tools/call`, plus the one-sentence client-auth reality note. Docs-only; no gem runtime
change. Builds on shipped specs 0001–0006 (archived — tenancy already stripped). Requirements are
testable; acceptance criteria are Given/When/Then. Governing principle: convenience + wiring only
(ADR-0007); the recipe documents existing seams, it adds no policy/auth to the gem.

---

## Background

The gem installs and secures, but the docs stop at "secure the endpoint" — the last mile from
"installed" to "a working `tools/call`" is missing. The stamped bearer example
(`User.staff.find_by(api_token: token)` in `mcp_controller.rb.tt`) depends on an `api_token`
column and a `staff` scope that no doc tells the operator to create. And there is no runnable
handshake showing a real MCP request. This spec adds both — in host-app setup docs and curl,
never in gem runtime.

---

## Scope

### In this spec

- A "Make your first call" recipe in `docs/USAGE.md` (full) and `README.md` (condensed).
- The client-auth reality note (static Bearer vs OAuth).
- A `CHANGELOG.md` `[Unreleased]` entry.

### Out of scope

- Any gem runtime/behavior change — none (docs only).
- OAuth / a real MCP-client connector — v1 is static Bearer over Streamable HTTP (ADR-0002/0003).

**DECIDED** the recipe puts the `api_token` migration, `SecureRandom.hex(24)` seed, `staff`
scope, and bearer resolution in **host-app setup docs and curl** — not in gem runtime; they
document the existing commented template example.

**DECIDED** the handshake is shown as pasteable `curl`: an `initialize` POST, a `tools/list`,
then a `tools/call` for the shipped `example_read_only` tool, each with
`Authorization: Bearer <token>` against `/mcp`.

---

## Requirements

### R1 — Token setup matching the shipped bearer example

- **Given** `docs/USAGE.md`, **when** read, **then** it shows the host-app setup the stamped
  bearer path needs: an `api_token` column migration, a `SecureRandom.hex(24)` seed for a staff
  user, and a `staff` scope — matching `mcp_controller.rb.tt`'s example
  `User.staff.find_by(api_token: token)`.
- **Given** the recipe, **when** followed, **then** it also states that `ApplicationMcpTool#authorize`
  must be overridden to permit the staff user (the gem default denies), so the first call is not
  blocked by a fail-closed `authorize`.

### R2 — Runnable JSON-RPC handshake

- **Given** `docs/USAGE.md`, **when** read, **then** it gives pasteable `curl` for the full
  handshake against `/mcp` with `Authorization: Bearer <token>`: `initialize`, then `tools/list`
  (shows `example_read_only`), then `tools/call` of `example_read_only` — ending in a real tool
  result.
- **Given** `README.md`, **when** read, **then** it carries a condensed version of the same
  recipe (Gemfile git line → `rails g rails_mcp:install` → wire auth → curl `tools/call`).
- **Given** the recipe's tool name and route, **when** checked against the shipped code, **then**
  they match: tool `example_read_only`, route `POST /mcp` → `mcp#handle`.

### R3 — Client-auth reality note

- **Given** `docs/USAGE.md`/`README.md`, **when** read, **then** one sentence sets expectation:
  v1 is a static `Authorization: Bearer` over Streamable HTTP; validate with `curl` or an MCP
  inspector that accepts a custom header; Claude's hosted remote-MCP connector expects OAuth
  2.1, so a static Bearer from that surface is not guaranteed (do not promise it).

### R4 — Changelog

- **Given** `CHANGELOG.md`, **when** read, **then** its `[Unreleased]` section records the
  tenancy strip (spec 0006), the `dummy_app` removal, the doc seam/route corrections, and this
  Getting-started recipe.

### R5 — No gem runtime change

- **Given** `lib/`, **when** compared, **then** it is unchanged by this spec (docs/CHANGELOG
  only); the recipe documents existing seams, adding no policy or auth to the gem.

---

## Non-goals (guardrails)

- No gem runtime, template, or behavior change (R5).
- No OAuth / client-connector implementation (out of scope for v1).
- No promise that a specific hosted MCP client connects with a static Bearer (R3 sets the
  expectation instead).
