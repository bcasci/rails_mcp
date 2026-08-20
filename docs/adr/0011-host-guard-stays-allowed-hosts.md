# ADR-0011 — Host guard stays `allowed_hosts`; reject `dns_rebinding_protection: false` default

Status: Superseded by ADR-0014 (2026-08-20)

## Context

The stamped `McpController` builds the `mcp` transport with
`allowed_hosts: Rails.application.config.hosts.grep(String)` so a production `Host` clears the
SDK's DNS-rebinding guard (the loopback-only default 403s a real deploy). A proposed
simplification was to instead pass `dns_rebinding_protection: false` and defer Host validation
to Rails' own `config.hosts` middleware.

Reading mcp 1.1.0: `dns_rebinding_protection: false` returns early from
`validate_request_headers`, disabling **both** the Host check **and** the Origin check
(`validate_host || validate_origin`). The MCP spec says servers MUST validate the `Origin`
header; Rails `config.hosts` validates `Host` but nothing in Rails validates the MCP `Origin`.
So the "simpler" default silently drops a check the gem's transport otherwise performs.

## Decision

The stamped controller keeps `allowed_hosts: Rails.application.config.hosts.grep(String)` and
does **not** default `dns_rebinding_protection: false`. Two behavioral integration tests prove
it (a production host in `config.hosts` passes; an unlisted host 403s). `dns_rebinding_protection:
false` may be mentioned in a controller comment as an option for deployments whose upstream
proxy already validates Host and Origin — never as the shipped default.

## Consequences

- The generated endpoint validates both Host and Origin out of the box, per the MCP spec.
- `config.hosts` must include the app's production host (true for any correctly-configured
  Rails deploy); the Getting-started recipe has the operator confirm it.
- Records the rejected simplification so it is not revisited. Consistent with ADR-0002
  (HTTP-only, stateless transport).
