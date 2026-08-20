# REVIEW.md — code-review standards for rails_mcp

Instructions for `/code-review`. Priority: correctness bugs first, then the invariants
below, then tests, then spec adherence, then cleanups. Every behavior claim in a finding
needs a `file:line` citation — no speculative findings.

## Highest-severity invariants (treat as Important)

- **No arbitrary-Ruby/console path** — no generic executor tool; the only callable surface
  is registered `RailsMcp::Tool` subclasses. The dynamic-dispatch grep must cover ALL of
  these forms: the eval-family (`eval`, `instance_eval`, `class_eval`, `module_eval`,
  `binding.*`) PLUS `constantize`, `const_get`, `public_send`, and `send`/`__send__` with a
  non-literal argument. A form on this list that the grep does not check is a coverage gap;
  the grep-enforcement is a code-spec requirement, cross-ref SEC-04 (no check is asserted to
  run until named in CI). (ADR-0004, SPEC R10)
- **Gem ships no policy** — no authorization logic, audit persistence, identity resolution,
  or tenant/shard code in `lib/`. Those belong in the app-owned `ApplicationMcpTool`. Flag
  any that appear in gem code. (ADR-0004)
- **No hand-rolled JSON-RPC or transport** — protocol is delegated to the official `mcp`
  gem. (ADR-0001)
- **`authorize` defaults fail closed (deny).** Flag any default-allow. (SPEC R3)
- **No bearer token or credential** in a notification payload or any log line. (SPEC R4)
- **No secret or stack leak in a surfaced tool error.** Operationalize this: every shipped
  `authorize`/`perform` example and the gem's default deny message must be verified against
  `mcp`'s surfacing — a raised error reaches the client as `Internal error calling tool
  <name>: <e.message>`, so the message must carry no record ids, SQL, or internal class
  names. Developer detail belongs in the notification payload/logs, never the raised message.
  Flag any `perform` example that interpolates untrusted or internal data into a `raise`.

## Tests (a gap here is Important, not a nit)

- Every changed behavior tied to a SPEC requirement has a test asserting its acceptance
  criteria. A public seam change with no test is a finding.
- Flag tautological/always-green tests, tests with no meaningful assertion, and duplicate
  coverage of a behavior already tested elsewhere.
- **Over-mocking is a finding.** Flag: mocks of the unit under test or the gem's own classes;
  a stub returning a shape the real method never produces; a stubbed `mcp`-gem surface with no
  real-transport integration test on the same path; an all-mocks suite. A green test over an
  unrealistic stub is a real bug hiding. (Interaction assertions ARE correct for fire-and-forget
  side effects — "notification fired exactly once / not on deny" — and command ordering; don't
  flag those.)
- **Diverging/stub harness is a finding.** An integration test must exercise the stamped/
  generated artifact verbatim. Flag a test that adds what the artifact omits (an `allowed_hosts`,
  a header), swaps the real base class (`ActionController::Base` for `ApplicationController`), or
  stubs the hard part (a fake tenant with no real `with_shard`) — the divergence hides the bug
  it claims to cover. The verbatim-template fixture (`test/integration/fixture_app/`) is the bar.
  Once a verbatim-template integration fixture exists for a flow, a SECOND hand-mirrored
  integration test of the same flow is a finding — redundant AND diverging, even if green:
  delete it and migrate any unique assertion onto the verbatim fixture. One integration file
  per flow. (SPEC R12, TEST-03)
- **Doc tests must guard code, not prose.** Asserting that prose/marketing sentences appear in
  a `.md` file is a finding — a passing prose-regex proves presence, not correctness. A docs
  test is allowed ONLY when it (a) asserts a literal code token in the doc equals the same
  token in shipped code (a drift guard) or (b) executes an example extracted from the doc and
  asserts its behavior. Posture-named test files (`*_hardening_`, `real_world_`, `smoke_`,
  `sanity_`, etc.) are findings. (SPEC R12, TEST-05, STD-03)
- **Credential and leak tests run on the REAL request path.** The no-credential-in-payload and
  no-secret/stack-leak invariants must be tested by a `tools/call` carrying an
  `Authorization: Bearer` through the controller, asserting the token appears in NEITHER the
  audit payload (including nested `args`) NOR the surfaced error — not only against a
  hand-built payload hash. A scrub test whose input never contained the secret at the level
  asserted is a tautology; flag it. (SPEC R12, TEST-06)
- **Integration-hazard completeness (Important, not a nit).** For a change on the gem↔app seam,
  check the real install path is covered: dev reload (Zeitwerk), cold boot, production
  `Host`/proxy, a second app profile (multitenant/sharded), host middleware (CSRF). Review
  grades conformance to the criteria that exist — so a missing criterion here ships green unless
  you name it. Ask "what does a fresh, real install still fail at?" and flag the gap.

## Spec adherence

- Changes map to a SPEC requirement (R1–R12) and stay in **read-only v1** scope. Flag
  out-of-scope additions (mutating tools, approval flows, OAuth) — those are deferred.

## Conventions

- Enforce `docs/conventions.md`: tools/args named for what they are; seam names are frozen
  contracts; one behavior per test.

## Convergence

- On re-review, report only Important findings; suppress nits already raised.
