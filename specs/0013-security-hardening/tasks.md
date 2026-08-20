# TASKS — Security hardening of taught patterns and controls

Task breakdown for spec 0013. Each task owns a DISJOINT set of files. Builds on shipped specs
0001–0012 (archived). References like `R1` point to this spec's `spec.md`. Findings resolved:
SEC-01…SEC-05.

Every task is `autonomous`. T1–T4 are independent (disjoint files) and run in parallel; T5 (the
gate) depends on all four.

Ownership boundary: this spec fixes code/tests/docs only. It does NOT touch `docs/conventions.md`,
`REVIEW.md`, `CLAUDE.md`, or the spec-driven-dev skill — every `standards_amendment` is spec
0015's. `docs/SEAMS.md` and `docs/USAGE.md` are generated project docs and ARE editable here.

---

## Layer 0 — Fix taught patterns and controls (parallel, disjoint files)

### T1 — Secure the taught auth recipe (SEC-01)
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED: rewrite the bearer
  example COMMENT — anchored parse `[/\ABearer (.+)\z/, 1]`, digest lookup
  `find_by(api_token_digest: Digest::SHA256.hexdigest(token))`, no `.remove("Bearer ")`, no raw
  `find_by(api_token: token)`. Do NOT touch the `allowed_hosts`/transport lines — T3 owns those.)
- `README.md` (CHANGED: getting-started auth snippet → the secure recipe)
- `docs/USAGE.md` (CHANGED: the "Add the column" section → `api_token_digest`; the token-generation
  step stores the digest and shows the raw token once, "treat like a password — never logged"; the
  bearer seam → anchored parse + digest lookup; label any plaintext demo "demo only — do not ship")

**Note:** T1 owns the auth RECIPE prose in `docs/USAGE.md`; T2 owns the `perform`-error prose and
the SEAMS verbatim-surface note. Keep edits to disjoint sections (auth-seam section vs.
error/`perform` section). If both must touch USAGE, T1 owns lines about authentication/token
storage, T2 owns lines about `perform`/errors.

**Depends on:** shipped 0001–0012.
**Acceptance (R1):** no `.remove("Bearer ")` or raw `find_by(api_token: token)` in the three
files; anchored regex + digest-at-rest taught; plaintext demo (if any) labeled do-not-ship.
**Tag:** `autonomous`.

### T2 — Sanitize client-facing errors; document the verbatim surface (SEC-02)
**Owns:**
- `lib/rails_mcp/tool.rb` (CHANGED: default `authorize` raises `NotAuthorized, "not authorized"`;
  carry developer detail on the exception via a `detail:`/`#detail` attribute so the audit
  `error:` still identifies the denying class and the unimplemented seam. Invoke pipeline,
  one-event guarantee, arg-dropping, `perform`, `text_response`, `call` UNCHANGED. Do NOT convert
  `.send` here — T4 owns the SEC-05 send-site change; T2 leaves tool.rb:43 for T4. Coordinate: T2
  and T4 both touch tool.rb — see the split note below.)
- `docs/SEAMS.md` (CHANGED, error-surface section only: state that `authorize`/`perform` messages
  surface VERBATIM via mcp's `Internal error calling tool <name>: <e.message>`; instruct raising
  generic messages. Leave the "No credentials" grep line to T3.)
- `docs/USAGE.md` (CHANGED, `perform`/error section only: model `perform` with `find_by` + a
  generic error, never `Model.find(id)`; no example interpolates ids/SQL/class names into a raise)
- `test/rails_mcp/tool_test.rb` (or the existing default-deny test) (CHANGED/NEW: assert the raised
  message is exactly `"not authorized"` AND the audit event `error:`/exception detail retains the
  developer detail; assert exactly one event still fires on denial)

**tool.rb split with T4:** T2 changes the `NotAuthorized` message/detail and the `authorize`
default body (tool.rb ~88-92). T4 changes only `new.send(:invoke, …)` → `new.__send__(:invoke, …)`
(tool.rb:43). These are non-overlapping lines. Sequence T4 after T2 if the builder cannot edit the
same file in parallel; otherwise the hunks are disjoint. **Decision: T2 owns tool.rb; T4's
tool.rb:43 one-line change is folded into T2's edit of tool.rb (T2 makes both edits), so tool.rb
has a single owner.** T4 then owns only args.rb, the grep task, and the pre-commit hook.

**Depends on:** shipped.
**Acceptance (R2):** raised message `"not authorized"`; developer detail in audit `error:`; one
event on denial; docs state the verbatim surface; no `Model.find(id)` in the modeled `perform`.
**Tag:** `autonomous`.

### T3 — Fix stamped `allowed_hosts`; exercise empty-config.hosts (SEC-03)
**Owns:**
- `lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt` (CHANGED, transport lines
  ONLY: add `dns_rebinding_protection: Rails.application.config.hosts.grep(String).any?`, keep
  `allowed_hosts: …grep(String)`, add the stamped warning comment that `config.hosts` is empty in
  production so the guard is OFF until populated / validated at the proxy, and how to force it on.
  Do NOT touch the auth-seam comment — T1 owns that.)
- `test/integration/fixture_app/boot.rb` (CHANGED: allow booting the fixture WITHOUT
  `config.hosts << PRODUCTION_HOST` so the empty-config default is testable; keep a populated-host
  boot path for the guard-active assertion)
- `test/integration/real_world_hardening_test.rb` (CHANGED/NEW cases: (a) EMPTY `config.hosts` →
  a real request is NOT 403'd by the Host guard; (b) populated `config.hosts` → foreign Host
  rejected, listed Host accepted)

**Note:** T1 and T3 both edit `mcp_controller.rb.tt` but disjoint regions (auth-seam comment vs.
transport construction). If the builder cannot co-edit, sequence T3 after T1. **Decision: keep the
two regions disjoint; the template has both hunks applied — assign a single builder both hunks if
parallel editing of one file is unsafe.** (Planner may merge T1+T3's template hunk into one
builder while keeping the doc edits split.)

**Depends on:** shipped.
**Acceptance (R3):** stamped `dns_rebinding_protection` guards only when hosts present; warning
comment stamped; integration test covers the empty-config case and the populated case.
**Tag:** `autonomous`.

### T4 — Shared `adr:check` rake task with credential + extended-dispatch greps (SEC-04, SEC-05)
**Owns:**
- `tasks/adr_check.rake` (NEW) or the `Rakefile` (CHANGED): define `adr:check` running — the
  existing `binding.pry`/`irb` and eval-family greps; the extended dynamic-dispatch grep adding
  `constantize`, `\bconst_get`, `public_send`, bareword `\.send\(`; a credential-pattern grep over
  `lib/` and `lib/generators/**/templates/`; and the ADR-0004 policy/tenant grep. Make `adr:check`
  a prerequisite of `default` (so CI's `bundle exec rake` runs it).
- `.githooks/pre-commit` (CHANGED: replace the inline grep block with `bundle exec rake adr:check`)
- `lib/rails_mcp/args.rb` (CHANGED, line 119 only: `superclass.send(:arg_definitions)` →
  `superclass.__send__(:arg_definitions)`)
- `lib/rails_mcp/tool.rb` (CHANGED, line 43 only: `new.send(:invoke, …)` →
  `new.__send__(:invoke, …)`) — **folded into T2's ownership of tool.rb per the T2 split note**;
  if T2 already made this change, T4 does not touch tool.rb.
- `test/adr_check_test.rb` (NEW: planted-violation cases — a bareword `.send(x)`, `.constantize`,
  `const_get`, `public_send`, a raw-credential store, a `tenant`/`shard` reference — each makes
  `rake adr:check` (or the grep it runs) exit non-zero; a clean tree passes)
- `docs/SEAMS.md` (CHANGED, the "No credentials" line ONLY: name `rake adr:check` as the enforcing
  check now that the credential grep exists — replacing "guarded by CI grep". Disjoint from T2's
  error-surface edit to SEAMS.)

**SEAMS split with T2:** T2 edits SEAMS's error-surface section; T4 edits SEAMS's "No credentials"
line. Disjoint lines. If co-editing one file is unsafe, sequence T4 after T2. **Decision: assign
both SEAMS hunks to one builder if parallel single-file edits are unsafe; otherwise disjoint.**

**Depends on:** shipped. (tool.rb dependency resolved by folding tool.rb:43 into T2.)
**Acceptance (R4, R5):** `adr:check` exists, is run by pre-commit AND by `default`/CI; credential +
policy/tenant + extended-dispatch greps present; planted violations fail; no bareword `.send(` in
`lib/`; SEAMS names the real check.
**Tag:** `autonomous`.

---

## Layer 1 — Gate

### T5 — Full gate + spec self-checks
**Owns:** (no source files; runs checks only)
- Run `bundle exec rake` (minitest + standardrb + `adr:check`) — green.
- `grep -RnE '\.remove\("Bearer ' README.md docs/USAGE.md lib/generators` → no matches (R1).
- `grep -RnE 'find_by\(api_token:' README.md docs/USAGE.md lib/generators` → no matches (R1).
- `grep -RnE '\.send\(' lib/` → no matches (R5; both sites are `__send__`).
- `grep -RnE 'Model\.find\(' docs/USAGE.md` → no matches in a `perform` example (R2).
- Confirm `adr:check` is a prerequisite of `default` and pre-commit calls it (R4).
- Confirm the integration suite exercises the empty-`config.hosts` case (R3).
- Confirm the raised default-deny message is `"not authorized"` and the audit `error:` keeps the
  developer detail (R2).
- Confirm no edits landed in `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the
  spec-driven-dev skill (`git diff --name-only` shows none) — standards amendments are spec 0015's.

**Depends on:** T1, T2, T3, T4.
**Acceptance:** `bundle exec rake` green; all self-checks above pass; ownership boundary respected.
**Tag:** `autonomous`.

---

## Dependency graph

```
(shipped 0001-0012)
T1 ┐
T2 ┼─→ T5
T3 ┤
T4 ┘
```

T1–T4 parallel (disjoint files, with tool.rb consolidated under T2 and the shared-file hunks noted
above); T5 gates.

---

## Decisions

**DECIDED (locked in spec.md — do not relitigate):**
- SEC-01: taught recipe = digest-at-rest (`api_token_digest`, SHA256), anchored parse
  `[/\ABearer (.+)\z/, 1]`, no plaintext store, no `.remove("Bearer ")`, no raw
  `find_by(api_token:)`; plaintext demo (if any) labeled "demo only — do not ship".
- SEC-02: default `NotAuthorized` raised message = `"not authorized"`; developer detail moves to
  the exception's `#detail` and the audit `error:`; modeled `perform` uses `find_by` + generic
  error; docs state the verbatim client surface. Invoke pipeline / one-event unchanged.
- SEC-03: `dns_rebinding_protection: config.hosts.grep(String).any?` + stamped warning; guard fails
  open on the Host header only; test the empty-config case.
- SEC-04: shared `rake adr:check` run by pre-commit AND `default`/CI; adds credential + ADR-0004
  policy/tenant greps; SEAMS names the real check.
- SEC-05: grep flags `constantize`/`const_get`/`public_send`/bareword `.send(`; the two safe sites
  become `__send__` of a literal.
- Ownership: no edits to `docs/conventions.md`, `REVIEW.md`, `CLAUDE.md`, or the spec-driven-dev
  skill — all `standards_amendment`s are consolidated in spec 0015.

No open decisions remain — every task is `autonomous`.
