# ADR-0014 — Stamped Host guard tracks `config.hosts`; fails open when it is empty

Status: Accepted (2026-08-20)

Supersedes ADR-0011.

## Context

ADR-0011 kept the stamped `McpController` transport at `allowed_hosts:
Rails.application.config.hosts.grep(String)` and refused to default
`dns_rebinding_protection: false`, so the SDK guard validated both Host and Origin "out of
the box." Its stated assumption: `config.hosts` includes the app's production host for "any
correctly-configured Rails deploy," and the Getting-started recipe has the operator confirm
it.

That assumption is false for a standard production app. `config.hosts` is auto-populated only
in **development**; a stock production Rails app leaves it **empty**. With the guard hard-on
and `allowed_hosts` empty, mcp's DNS-rebinding guard falls back to loopback-only and returns
`403 Forbidden: Invalid Host header` on **every** real request — a day-one outage the operator
cannot diagnose without reading mcp internals (spec 0013, SEC-03). ADR-0011's two integration
tests never caught this because the fixture seeded a production host into `config.hosts`
(`boot.rb` did `config.hosts << PRODUCTION_HOST`), so the empty-config production default was
never exercised. This is the integration-reality gap `docs/conventions.md` names: a stamped
default that reads a Rails config value must be tested at that value's production default, not
a fixture-populated one.

Options considered: (a) keep ADR-0011 and document that operators must populate `config.hosts`
— rejected: it ships a broken default and blames the operator for the gem's foot-gun; (b)
default `dns_rebinding_protection: false` outright — rejected for the same reason ADR-0011
rejected it (it silently drops the Origin check the MCP spec requires, and hides the guard
from operators who *have* configured hosts); (c) tie the guard to whether `config.hosts`
actually holds String hosts.

## Decision

The stamped controller sets `dns_rebinding_protection:
Rails.application.config.hosts.grep(String).any?` while still passing `allowed_hosts:
Rails.application.config.hosts.grep(String)`. The guard is ON once the operator populates
`config.hosts` (validating both Host and Origin, as ADR-0011 required for that case) and OFF
while `config.hosts` is empty — the standard production default — so a real request is not
403'd on day one. A prominent stamped comment states that the guard is off until `config.hosts`
is populated, why (`config.hosts` is empty in production), and the three ways to re-enable it
(populate `config.hosts`, validate Host at the proxy, or force `dns_rebinding_protection:
true`).

This **fails open on the Host/Origin check only**. Authentication and authorization remain
fail-closed regardless (ADR-0004): a request that clears the Host guard still has no acting
user and no `authorize` grant until the app implements those seams.

## Consequences

- The stamped endpoint works on a standard production deploy without the operator first
  populating `config.hosts`, removing the day-one outage ADR-0011 shipped.
- The DNS-rebinding guard (Host + Origin) is no longer on by default; it activates only once
  `config.hosts` holds a String host. Operators who need it on before configuring hosts must
  force it via the stamped comment's instructions. The security posture is weaker on the Host
  header by default than ADR-0011 intended — this is the deliberate trade to avoid the outage,
  bounded to the Host/Origin check and never touching auth.
- The integration suite now exercises the EMPTY-`config.hosts` case at its production default
  (a real request is not 403'd) alongside the populated case (foreign Host 403'd, listed Host
  accepted). The fixture must not add the host in the empty-case test (spec 0013 R3;
  `docs/conventions.md` "Integration reality").
- ADR-0011's rejection of a *blanket* `dns_rebinding_protection: false` default still stands:
  the guard is not disabled outright, it is tied to configuration. ADR-0002 (HTTP-only,
  stateless transport) is unaffected.
