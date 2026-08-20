# ADR-0015 — rails_mcp depends on no `mcp` private internals; a drift test pins the public behavior it relies on

Status: Accepted (2026-08-20)

## Context

ADR-0001 delegates the protocol to the official `mcp` gem: rails_mcp is a thin
conventions-and-seams layer and does not reimplement JSON-RPC, transport, schemas, or
annotations. That delegation only holds if rails_mcp reads `mcp` through its **public**
surface.

The spec-0001 args allow-list has to distinguish two states `mcp` does not expose publicly:
"the app set a raw `input_schema`" vs "the app used only `arg`/nothing." The original
implementation reached for `mcp`'s private `@input_schema_value` ivar via
`instance_variable_get` (`lib/rails_mcp/args.rb`). The gemspec pins `mcp "~> 1.1"`, which
permits any 1.x minor, so a rename of that ivar in `mcp` 1.2+ would silently flip
`explicitly_set_input_schema?` — the args allow-list would misbehave with no failing test
(spec 0014, ARCH-01). A raw-schema tool also lost data downstream of that same read: with no
`arg` declarations its allow-list was empty, so every incoming argument was dropped before
`perform`, even though the advertised schema required it (ARCH-02).

A `~>` upper bound was considered and rejected as the guardrail: a version pin is a coarse
proxy, not a contract, and does not tell you *what* broke.

## Decision

rails_mcp reads no `mcp` private internal. Any distinction `mcp`'s public surface cannot
express, rails_mcp tracks in **its own state**: the `input_schema` setter override records
`@explicit_input_schema = true` on the tool class, and `explicitly_set_input_schema?` reads
that flag — never `mcp`'s `@input_schema_value`.

The `mcp` behaviors rails_mcp relies on but does not own are pinned by a **contract/drift
test** (`test/rails_mcp/mcp_contract_test.rb`) that asserts them through `mcp`'s *public* API
(e.g. a bare `MCP::Tool` advertises an empty `input_schema_value.to_h[:properties]`; a
raw-set schema advertises its properties). A `bundle update mcp` that changes the relied-on
contract fails that test instead of silently corrupting the allow-list. The drift test — not
a version bound — is the guardrail.

The args allow-list is derived from the tool's **effective** input schema: when an explicit
schema is set, the allow-list is that schema's `properties` keys as symbols; otherwise the
`arg`-declared names. This keeps the read off private state and, as a consequence, lets a
raw-schema tool round-trip its declared properties to `perform` while still dropping
undeclared args.

## Consequences

- The delegation boundary of ADR-0001 is now enforceable: rails_mcp's guarantees rest on its
  own state and on tests, not on `mcp` internals or undocumented invariants.
- When rails_mcp needs a distinction `mcp` does not expose, the pattern is fixed: track it in
  rails_mcp state at class-definition time and pin the underlying `mcp` behavior with a public
  contract test — do not read a private ivar and do not lean on the version pin.
- A `mcp` release that changes a relied-on public behavior surfaces as a named failing
  contract test, pointing at exactly what to reconcile.
- Standing constraint (guardrail = the drift test, not CI grep in this spec):
  `grep -rn "@input_schema_value" lib/` must return nothing. A future `rake adr:check` grep
  banning `instance_variable_get` of `mcp` ivars in `lib/` could harden this further; spec
  0015 owns any such standards amendment.

---
Immutable once Accepted. To change the decision, add a NEW ADR that supersedes this one, set
this file's Status to "Superseded by ADR-XXXX", and link both ways. Never rewrite the
Decision or Context of an accepted ADR — only its status, links, and typo fixes.
