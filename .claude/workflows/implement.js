export const meta = {
  name: 'implement',
  description:
    'Spec-driven factory build of rails_mcp from TICKETS.md — test-first builder agents per ticket in dependency order, a per-layer gate + heal loop using tests as the oracle, an integration audit, and a reflect stage that records ADRs/learnings. Pass a ticket id (e.g. "T3") to build just that ticket.',
  phases: [
    { title: 'Build' },
    { title: 'Gate' },
    { title: 'Audit' },
    { title: 'Reflect' },
  ],
}

// Dependency layers from TICKETS.md:  T0 -> {T1,T2,T3,T5} -> T4 -> T6 -> {T7,T8}
const LAYERS = [
  ['T0'],
  ['T1', 'T2', 'T3', 'T5'],
  ['T4'],
  ['T6'],
  ['T7', 'T8'],
]

const RESULT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['work_id', 'status', 'summary'],
  properties: {
    work_id: { type: 'string', description: 'ticket id (e.g. T3), a layer label, or "integration"' },
    status: { type: 'string', enum: ['pass', 'fail', 'blocked'] },
    summary: { type: 'string' },
    files_touched: { type: 'array', items: { type: 'string' } },
    criteria_covered: {
      type: 'array',
      items: { type: 'string' },
      description: 'SPEC requirement/criterion ids that now have a passing test',
    },
    test_names: { type: 'array', items: { type: 'string' } },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'summary'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          dimension: { type: 'string' },
          spec_ref: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'integer' },
          summary: { type: 'string' },
        },
      },
    },
    open_questions: {
      type: 'array',
      items: { type: 'string' },
      description: 'unresolved OPEN: forks that need Brandon before this ticket can finish',
    },
  },
}

const CONTEXT = `Repo: the rails_mcp gem at the working-tree root. Read SPEC.md (the build
contract), TICKETS.md (the breakdown), docs/conventions.md (naming/invariants/layout), and
the docs/adr/ decisions. Follow the .claude/skills/spec-driven-dev skill. Never bypass the
pre-commit gate (--no-verify is denied). Only touch files your ticket owns.`

const builderPrompt = (t) => `${CONTEXT}

You are the builder for ticket ${t}. Do this:
1. Read ticket ${t} in TICKETS.md: its owned files, dependencies, referenced SPEC
   requirements, and its tag.
2. Read those SPEC requirements. Their acceptance criteria are your test list.
3. If ${t} touches the MCP protocol, tool schema, Rack transport, or annotations, fetch the
   official mcp gem's current API first (context7 or its docs). Do NOT invent its API.
4. If ${t} is needs-human-oracle and a referenced OPEN: is unresolved, set status "blocked",
   put the exact question in open_questions, and do not guess the decision.
5. Otherwise: test-first. Write failing tests from the acceptance criteria (one behavior per
   test, cite the requirement id), then implement to green in ${t}'s owned files only.
   While iterating run ONLY your ticket's own test file(s) — the layer gate runs the full
   suite. Clean to docs/conventions.md.

Return the schema: work_id="${t}", status, files_touched, criteria_covered (SPEC ids with
passing tests), test_names, findings, open_questions.`

const gatePrompt = (layer) => `${CONTEXT}

Layer [${layer.join(', ')}] builders just finished. Run the full mechanical gate on the
working tree:
- bundle exec standardrb
- bundle exec rake test  (the full suite)
- the ADR-constraint greps in .githooks/pre-commit (no eval/console, no debugger)
Do NOT fix anything — only report. If everything is green, stage all changes and commit with
message "build: layer ${layer.join('+')}" (this runs the pre-commit hook; a failing hook
means the gate fails). Return the schema with work_id="layer ${layer.join('+')}",
status="pass" only if committed green, else "fail" with findings naming the failing files
and tests.`

const healPrompt = (layer, gate) => `${CONTEXT}

The gate for layer [${layer.join(', ')}] failed:
${JSON.stringify(gate && gate.findings ? gate.findings : gate, null, 2)}

Fix the failures within this layer's owned files only (do not touch other layers' files).
Re-run the failing tests/linter to confirm. Return the schema (work_id="heal ${layer.join('+')}").`

const auditPrompt = () => `${CONTEXT}

All layers are built and committed. Act as an INDEPENDENT integration auditor (you did not
write this code). Do:
- Run the full suite and standardrb; confirm green.
- Walk SPEC.md R1–R12 and confirm each requirement's acceptance criteria have a passing
  test. List any requirement with no covering test as a finding.
- Confirm the invariants hold in lib/: no arbitrary-Ruby/console path, no gem-side policy or
  tenant logic, no hand-rolled JSON-RPC, authorize fails closed, no credential in the
  notification payload.
Do not fix — report only. Return the schema with work_id="integration", status, findings,
and criteria_covered (the SPEC ids you verified).`

const reflectPrompt = () => `${CONTEXT}

The build burst is done. Review the whole diff on this branch. If it made a durable,
architecturally-significant decision not already recorded, write an ADR in docs/adr/ (use
docs/adr/_template.md, immutable-once-accepted rules). If it produced a reusable convention
or gotcha, add a line to CLAUDE.md. Record the "why" now while context is fresh. Then
summarize what you recorded (or that nothing warranted recording).`

// ---- run ----

const single = typeof args === 'string' && args.trim() ? args.trim() : null
const layers = single ? [[single]] : LAYERS

for (const layer of layers) {
  phase('Build')
  const built = (await parallel(
    layer.map((t) => () => agent(builderPrompt(t), { label: `build:${t}`, phase: 'Build', schema: RESULT_SCHEMA }))
  )).filter(Boolean)

  const blocked = built.filter((r) => r.status === 'blocked')
  if (blocked.length) {
    log(`⛔ Layer [${layer.join(', ')}] blocked on unresolved OPEN: decisions — stopping for Brandon.`)
    return { stoppedAt: layer, reason: 'blocked', blocked }
  }
  log(`Layer [${layer.join(', ')}] built: ${built.filter((r) => r.status === 'pass').length}/${layer.length} builder-pass`)

  phase('Gate')
  let round = 0
  let gate = await agent(gatePrompt(layer), { label: `gate:${layer.join('+')}`, phase: 'Gate', schema: RESULT_SCHEMA })
  while ((!gate || gate.status !== 'pass') && round < 3) {
    round += 1
    await agent(healPrompt(layer, gate), { label: `heal:${layer.join('+')}#${round}`, phase: 'Gate', schema: RESULT_SCHEMA })
    gate = await agent(gatePrompt(layer), { label: `gate:${layer.join('+')}#${round}`, phase: 'Gate', schema: RESULT_SCHEMA })
  }
  if (!gate || gate.status !== 'pass') {
    log(`⚠ Layer [${layer.join(', ')}] not green after ${round} heal rounds — stopping for human review.`)
    return { stoppedAt: layer, reason: 'gate-failed', gate }
  }
  log(`✓ Layer [${layer.join(', ')}] committed green.`)
}

phase('Audit')
const audit = await agent(auditPrompt(), { label: 'integration-audit', phase: 'Audit', schema: RESULT_SCHEMA })

phase('Reflect')
const reflect = await agent(reflectPrompt(), { label: 'reflect', phase: 'Reflect' })

return { audit, reflect }
