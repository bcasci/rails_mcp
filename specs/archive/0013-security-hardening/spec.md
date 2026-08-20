# SPEC — Security hardening of taught patterns and controls

> **Build order: 4 of 6.** Recommended sequence: 0015 → 0010 → 0011 → 0013 → 0014 → 0012. Depends on: 0011. GitHub does not enforce spec order — see the release tracking issue.

Build contract for spec 0013: close five security findings where the gem **teaches** or
**claims** a safety property it does not deliver — an insecure auth recipe operators copy
verbatim, client-facing error messages that leak internals, a stamped `allowed_hosts` default
that 403s every production request, and two "enforced by CI grep" claims whose grep either
does not run in CI or does not catch the dispatch forms it names. Builds on shipped specs
0001–0012 (archived). Given/When/Then acceptance criteria; `DECIDED` marks settled choices.

In force: ADR-0004 (zero gem-side policy/tenancy), ADR-0005 (per-request identity),
ADR-0012 (neutral conduit), ADR-0013 (app-owned tool list). Nothing here changes the gem's
guarantees — fail-closed, allow-list (mcp's), arg-dropping, one audit event per call,
per-request identity, read/write neutrality, zero gem-side policy. These are safety fixes to
taught patterns and to the enforcement of standing constraints, not behavior changes.

---

## Background

The gem is pitched as a safer replacement for a raw Rails console: an allow-list of app tools
the AI may call, with authentication and authorization as app-owned seams. Five findings show
the *taught* surface undermining that pitch:

- **SEC-01** — the canonical getting-started auth recipe (in `README.md`, `docs/USAGE.md`, and
  the stamped `mcp_controller.rb.tt` comment) stores the bearer token cleartext in an indexed
  column, compares it with plain `find_by` equality (not constant-time), and parses the header
  with `.to_s.remove("Bearer ")` — a global gsub that neither requires the `Bearer ` scheme nor
  survives a token containing the substring `Bearer `.
- **SEC-02** — `mcp` (server.rb:798) surfaces any tool raise to the AI client verbatim as
  `Internal error calling tool <name>: <e.message>`. `RailsMcp::Tool` re-raises whatever
  `authorize`/`perform` raised (tool.rb:74), and the default `NotAuthorized` message
  interpolates `self.class.name` (tool.rb:88-92). `docs/USAGE.md` models `perform` doing
  `Model.find(id)` (a `RecordNotFound` carrying ids). REVIEW.md:19 lists "no secret or stack
  leak in a surfaced tool error" as a highest-severity invariant the gem itself violates.
- **SEC-03** — the stamped controller passes
  `allowed_hosts: Rails.application.config.hosts.grep(String)`. `config.hosts` is auto-populated
  only in development; in a standard production app it is empty, so `allowed_hosts` is loopback
  only and the SDK DNS-rebinding guard 403s every real request — a day-one outage the operator
  can't diagnose without reading mcp internals. The integration fixture masks this: `boot.rb`
  does `config.hosts << PRODUCTION_HOST`, so the empty-config case is never exercised.
- **SEC-04** — `docs/SEAMS.md`, `CLAUDE.md`, and `.githooks/pre-commit` all assert the
  ADR/credential constraints are "guarded by CI grep". Reality: the pre-commit hook greps `lib/`
  for `binding.pry`/`irb` and eval-family only; there is no credential grep anywhere, no
  ADR-0004 policy/tenant grep, and the CI workflow runs `bundle exec rake` (Rakefile default =
  `test standard`) — it never runs the hook and has no grep step.
- **SEC-05** — the one grep that exists
  (`\b(instance_eval|class_eval|Kernel\.eval|[^.]\beval)\(`) catches only literal eval-family.
  `constantize`, `Object.const_get`, `public_send`, and `record.send(user_input)` — the
  idiomatic Rails ways to turn an AI-supplied string into a class or method — all pass it,
  exactly where a generic executor REVIEW.md forbids would be written.

---

## Scope

### In this spec

- Rewrite the taught auth recipe to the secure form across `README.md`, `docs/USAGE.md`, and the
  `mcp_controller.rb.tt` bearer example comment: digest-at-rest, `secure_compare`, anchored
  scheme parse. (SEC-01)
- Sanitize client-facing errors: a terse default `NotAuthorized` client message with developer
  detail preserved in the audit payload; document in `docs/SEAMS.md`/`docs/USAGE.md` that
  `authorize`/`perform` messages surface verbatim; change the modeled `perform` example off
  `Model.find(id)`. (SEC-02)
- Fix the stamped `allowed_hosts` default so a standard production app does not 403 every
  request, with a stamped warning comment; exercise the EMPTY-`config.hosts` case in the
  integration test. (SEC-03)
- Make the "CI grep" claim true: extract the constraint greps into a shared rake task run by
  BOTH pre-commit and the CI default task, add a credential-pattern grep and an ADR-0004
  policy/tenant grep, and correct the `docs/SEAMS.md` wording to match reality. (SEC-04)
- Extend the arbitrary-Ruby grep to cover `constantize`, `const_get`, `public_send`, and
  non-literal `.send(`; convert the two known-safe literal `.send(:sym)` call sites in
  `lib/rails_mcp/tool.rb` and `lib/rails_mcp/args.rb` to `__send__` of a literal so the grep can
  forbid bareword `.send(`. (SEC-05)

### Out of scope

- Any change to the invoke pipeline order (`authorize → perform → notify`), the one-event
  guarantee, arg-dropping, per-request identity, the allow-list (mcp's), or read/write
  neutrality. The default-deny stays fail-closed; only its *client-facing wording* changes and
  the developer detail moves to the audit payload.
- Editing `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the spec-driven-dev skill. Each
  finding carries a `standards_amendment`; **all standards amendments are tracked in spec 0015**
  (the CLAUDE.md/REVIEW.md/conventions.md wording for "generated example security", the
  operationalized REVIEW.md:19 error rule, the "integration reality production-default" rule,
  the "machine-checkable only if a named CI check runs it" rule, and the enumerated
  dynamic-dispatch forms). This spec ADDS the actual enforcing check and the code/doc fixes; it
  does not edit those four owned files. `docs/SEAMS.md` is generated project documentation and IS
  editable here (it is not one of the four owned files).

---

**DECIDED (SEC-01)** the taught recipe uses `has_secure_token`-style **digest at rest**: a
`api_token_digest` column resolved with `find_by(api_token_digest: Digest::SHA256.hexdigest(token))`,
compared for presence, and the raw header parsed with an anchored regex
`token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]`. Tokens are passwords —
never logged. A plaintext demo, if shown at all, is labeled "demo only — do not ship" as
prominently as the client-auth caveat box.

**DECIDED (SEC-02)** the default `NotAuthorized` raised message becomes the terse client string
`"not authorized"`. The developer detail (which class denied, that `authorize` is unimplemented)
moves into the audit event's `error:` payload via a developer-facing attribute on the exception
(e.g. `NotAuthorized#detail`), NOT the message. The invoke pipeline and one-event guarantee are
unchanged. Modeled `perform` examples use `find_by` + an explicit generic error, never
`Model.find(id)`.

**DECIDED (SEC-03)** the stamped controller keeps DNS-rebinding protection but makes it
non-fatal in the empty-`config.hosts` case: it stamps
`dns_rebinding_protection: Rails.application.config.hosts.grep(String).any?` (guard on when hosts
are configured, off when the production default leaves them empty) with a prominent stamped
comment that the operator MUST populate `config.hosts` (or validate Host at the proxy) to
re-enable the guard. `allowed_hosts:` still passes the String entries. This fails **open on the
Host guard only** — authentication and authorization remain fail-closed — and avoids the
day-one outage while telling the operator exactly what to do.

**DECIDED (SEC-04)** the shared task is `rake adr:check` (a plain rake task in a new
`tasks/adr_check.rake` or the Rakefile), invoked by `.githooks/pre-commit` and added as a
prerequisite of the `default` task so CI's `bundle exec rake` runs it. It runs: the existing
debugger + eval greps, the extended dynamic-dispatch grep (SEC-05), a credential-pattern grep
over `lib/` and `lib/generators/**/templates/`, and the ADR-0004 policy/tenant grep. `docs/SEAMS.md`
wording changes from "guarded by CI grep" to name the actual check.

**DECIDED (SEC-05)** the dynamic-dispatch grep flags `constantize`, `\bconst_get`,
`public_send`, and bareword `\.send\(`. The two safe call sites become `__send__(:invoke, …)`
(tool.rb:43) and `superclass.__send__(:arg_definitions)` (args.rb:119) so a bareword `.send(`
anywhere in `lib/` is a violation.

---

## Requirements

### R1 — Taught auth recipe is the secure form (SEC-01)

- **Given** the bearer example in the comment of
  `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt`, **when** read, **then** it
  (a) parses with the anchored regex `request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]`
  (not `.remove("Bearer ")`), (b) resolves via a digest column
  (`find_by(api_token_digest: Digest::SHA256.hexdigest(token))` or a documented `has_secure_token`
  equivalent), and (c) uses `ActiveSupport::SecurityUtils.secure_compare` OR relies on the digest
  lookup with a documented note that the digest column is the constant-time-safe form (no plain
  `find_by(api_token: token)` on a raw token). No plaintext token is stored in the taught path.
- **Given** `README.md` (the getting-started auth snippet) and `docs/USAGE.md` (the "Add the
  column" + bearer-seam sections), **when** read, **then** they teach the same digest-at-rest,
  anchored-parse recipe: the column is `api_token_digest` (not a raw `api_token`), the token is
  generated and its digest stored (raw token shown to the operator once, labeled "treat like a
  password — never logged"), and the seam parses with the anchored regex. No occurrence of
  `.remove("Bearer ")` or a raw `find_by(api_token: token)` remains in these three files.
- **Given** any plaintext-token demo retained for teaching, **when** read, **then** it is labeled
  "demo only — do not ship" at least as prominently as the existing client-auth caveat box.

### R2 — Client-facing errors are sanitized; the leak is documented (SEC-02)

- **Given** `lib/rails_mcp/tool.rb`, **when** the unoverridden `authorize` denies, **then** the
  **raised message** is the terse client string `"not authorized"` (no `self.class.name`, no
  "override … in ApplicationMcpTool" text in the message). The developer detail (denying class,
  that the seam is unimplemented) is carried on the exception as a separate developer attribute
  (e.g. `NotAuthorized#detail`) and reaches the audit event's `error:` payload, so operators keep
  full diagnosis in logs while the AI client sees only `"not authorized"`.
- **Given** the invoke pipeline, **when** a call is denied or raises, **then** exactly one
  `invoke.rails_mcp` audit event still fires (unchanged), and its `error:` still identifies the
  real failure. Verified by a test asserting: the surfaced/raised message is `"not authorized"`
  AND the audit payload's `error:` retains the developer detail.
- **Given** `docs/SEAMS.md` and `docs/USAGE.md`, **when** read, **then** they state explicitly
  that any message raised from `authorize`/`perform` surfaces VERBATIM to the AI client (via
  mcp's `Internal error calling tool <name>: <e.message>`), instruct apps to raise generic
  messages, and the modeled `perform` example uses `find_by` + an explicit generic error — no
  `Model.find(id)` (which would leak ids as `RecordNotFound`). No `perform` example in these docs
  interpolates record ids, SQL, or internal class names into a raise.

### R3 — Stamped `allowed_hosts` does not 403 a standard production app (SEC-03)

- **Given** `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt`, **when** read,
  **then** the transport is constructed with
  `dns_rebinding_protection: Rails.application.config.hosts.grep(String).any?` (guard active only
  when `config.hosts` holds String hosts), still passing
  `allowed_hosts: Rails.application.config.hosts.grep(String)`, and a stamped comment warns that
  `config.hosts` is empty in a standard production app, that the guard is therefore OFF until the
  operator populates `config.hosts` (or validates Host at the proxy), and how to force it on.
- **Given** the integration test for the stamped controller, **when** it runs, **then** it
  exercises the **EMPTY**-`config.hosts` case (no test-added production host) and asserts a real
  request is NOT 403'd by the Host guard — proving the stamped default does not cause a day-one
  outage. The existing populated-`config.hosts` path (guard active, foreign Host rejected) is
  also asserted. The fixture must not add the host in the empty-case test.

### R4 — "CI grep" is real: a shared task run in CI (SEC-04)

- **Given** the repository, **when** the constraint greps are located, **then** they live in a
  single shared rake task `adr:check` (in the Rakefile or a loaded `tasks/*.rake`) — not
  duplicated between the hook and CI.
- **Given** `.githooks/pre-commit`, **when** read, **then** it invokes `bundle exec rake adr:check`
  (replacing its inline grep block) so the hook and CI run the identical check.
- **Given** the `default` rake task, **when** `bundle exec rake` runs (as CI does), **then**
  `adr:check` runs as part of it and a violation fails the build. `adr:check` covers: the existing
  `binding.pry`/`irb` and eval-family greps, the extended dynamic-dispatch grep (R5), a
  credential-pattern grep over `lib/` and `lib/generators/**/templates/` (flagging a token/secret/
  bearer/password value being logged or stored raw in gem/stamped code), and an ADR-0004
  policy/tenant grep. A deliberately-planted violation of each pattern makes `rake adr:check` exit
  non-zero (proven by a test or a documented self-check in the task).
- **Given** `docs/SEAMS.md`, **when** the "No credentials" line is read, **then** it no longer
  claims a grep that does not exist: it either names `rake adr:check` as the enforcing check (now
  that the credential grep exists) or states the rule is a convention. The parallel wording in
  `CLAUDE.md` and `REVIEW.md` is a **standards amendment tracked in spec 0015** and is NOT edited
  here.

### R5 — Dynamic-dispatch grep covers the real executor forms (SEC-05)

- **Given** the dynamic-dispatch grep inside `adr:check`, **when** run against `lib/`, **then** it
  flags `constantize`, `\bconst_get`, `public_send`, and bareword `\.send\(` in addition to the
  eval-family — the forms an app tool would use to turn an AI-supplied string into a class or
  method.
- **Given** `lib/rails_mcp/tool.rb:43` and `lib/rails_mcp/args.rb:119`, **when** read, **then**
  the two known-safe fixed-symbol calls are `__send__(:invoke, …)` and
  `superclass.__send__(:arg_definitions)` respectively (literal symbol arguments), so no bareword
  `.send(` remains in `lib/` and the grep's `\.send\(` pattern has zero legitimate matches.
- **Given** a planted `foo.send(params[:x])`, `"X".constantize`, `Object.const_get(x)`, or
  `obj.public_send(y)` in `lib/`, **when** `rake adr:check` runs, **then** it exits non-zero. The
  enumeration of these forms in `REVIEW.md`/`CLAUDE.md` prose is a **standards amendment tracked
  in spec 0015**; this spec only implements the grep.

---

## Non-goals (guardrails)

- No change to the invoke pipeline order, the one-audit-event guarantee, arg-dropping,
  per-request identity, the allow-list (mcp's), or read/write neutrality. `authorize` stays
  fail-closed; only its client-facing wording changes (R2).
- No gem-side policy, tenancy, or invented identity (ADR-0004). The auth recipe stays a taught
  app-owned pattern; the gem still ships no authentication.
- No editing of `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the spec-driven-dev skill.
  Every `standards_amendment` from these findings is consolidated in **spec 0015**.
- No hand-rolled JSON-RPC/transport (ADR-0001); the `allowed_hosts`/`dns_rebinding_protection`
  fix stays a parameter passed to the mcp gem's transport.
- The Host-guard fix fails open on the Host header ONLY (R3); it must not weaken authentication or
  authorization, which remain fail-closed.
