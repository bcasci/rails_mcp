# ADR-0012 — The gem is a neutral MCP tool-exposure conduit

Status: Accepted (2026-08-13)

Supersedes: ADR-0003 (read-only v1). Clarifies the framing of ADR-0005 (the acting identity is
whatever the app resolves — not specifically a "staff" user). ADR-0004 (gem owns zero policy)
stands and is reinforced.

## Context

The gem accreted opinions at bootstrap that are not its concern: "read-only v1" (ADR-0003),
"act-as-staff-user" / "internal staff-only" identity framing (ADR-0005, R9), and tenancy
(removed in ADR-0010). None is enforced in code — `read_only!` only sets an advisory MCP
annotation; the invoke pipeline runs whatever `perform` does; `user:` is just the identity the
app hands in. These opinions live in docs, templates, and scope prose, and they repeatedly drove
scope-creep debates. The gem's actual job is narrow: let an app register tools and expose them
over MCP, with two app-owned seams.

## Decision

`rails_mcp` exposes app-defined tools to an MCP client and provides exactly two app-owned seams:
`authorize` (called before each tool runs) and a per-call `invoke.rails_mcp` notification. It
imposes **no policy of its own.** The following are **implementor decisions**, made in the app's
tool/controller/app code, and the gem takes no position on any of them:

- **Read vs write** — a tool's `perform` may do anything; the gem does not gate mutations.
  `read_only!` remains available as an optional, advisory MCP annotation the implementor may set.
- **Who may call, and how they authenticate** — the app's `McpController` decides.
- **Permissions** — the app's `authorize` decides.
- **Audience** — internal operators, end-users, or anything else; the gem does not care.
- **Tenancy, persistence, audit sink** — app code (ADR-0004/0010).

Any gem change that adds an opinion in those areas is out of scope.

## Consequences

- v1 is not "read-only." Apps expose read and/or write tools as they see fit; mutation needs no
  gem change. Human-in-the-loop approval, if an app wants it, is app code (or a future opt-in
  seam, not a gem-imposed gate).
- Docs, templates, README, `CLAUDE.md`, and `conventions` drop the read-only/staff/internal
  framing (spec 0008). The `user:` keyword and the two frozen seams are unchanged.
- Standing scope test: a proposed feature that decides read/write, identity, permission,
  audience, tenancy, or persistence for the app is rejected — the gem only registers tools,
  exposes them over MCP, calls `authorize`, and emits the notification.
- ADR-0003's deferral list (mutating tools, approval tiers) is void as a *gem constraint*;
  those are app concerns or optional future seams, not v1 gates.
