# REVIEW.md — code-review standards for rails_mcp

Instructions for `/code-review`. Priority: correctness bugs first, then the invariants
below, then tests, then spec adherence, then cleanups. Every behavior claim in a finding
needs a `file:line` citation — no speculative findings.

## Highest-severity invariants (treat as Important)

- **No arbitrary-Ruby/console path** — no `eval`, `instance_eval`, `class_eval`,
  `binding.*`, `send` to user input, or a generic executor tool. The only callable surface
  is registered `RailsMcp::Tool` subclasses. (ADR-0004, SPEC R10)
- **Gem ships no policy** — no authorization logic, audit persistence, identity resolution,
  or tenant/shard code in `lib/`. Those belong in the app-owned `ApplicationMcpTool`. Flag
  any that appear in gem code. (ADR-0004)
- **No hand-rolled JSON-RPC or transport** — protocol is delegated to the official `mcp`
  gem. (ADR-0001)
- **`authorize` defaults fail closed (deny).** Flag any default-allow. (SPEC R3)
- **No bearer token or credential** in a notification payload or any log line. (SPEC R4)
- No secret or stack leak in a surfaced tool error.

## Tests (a gap here is Important, not a nit)

- Every changed behavior tied to a SPEC requirement has a test asserting its acceptance
  criteria. A public seam change with no test is a finding.
- Flag tautological/always-green tests, tests with no meaningful assertion, over-mocking
  that asserts the mock instead of the behavior, and duplicate coverage of a behavior
  already tested elsewhere.

## Spec adherence

- Changes map to a SPEC requirement (R1–R12) and stay in **read-only v1** scope. Flag
  out-of-scope additions (mutating tools, approval flows, OAuth) — those are deferred.

## Conventions

- Enforce `docs/conventions.md`: tools/args named for what they are; seam names are frozen
  contracts; one behavior per test.

## Convergence

- On re-review, report only Important findings; suppress nits already raised.
