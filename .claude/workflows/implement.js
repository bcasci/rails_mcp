export const meta = {
  name: 'implement',
  description:
    'Spec-driven factory build. A planner reads a tickets file (default TICKETS.md) and derives the dependency-ordered build layers, then builder agents implement each ticket test-first, with a per-layer gate + heal loop, an integration audit, a reflect stage, and an archive. Pass nothing to build all; a ticket id ("T3") or set ("T1 T2") to build a subset; or a path to a different tickets file ("docs/v2/TICKETS.md") to build another spec.',
  phases: [
    { title: 'Plan' },
    { title: 'Build' },
    { title: 'Gate' },
    { title: 'Audit' },
    { title: 'Reflect' },
    { title: 'Archive' },
  ],
}

const PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['tickets_file', 'spec_file', 'layers'],
  properties: {
    tickets_file: { type: 'string' },
    spec_file: { type: 'string', description: 'the SPEC the tickets file references' },
    layers: {
      type: 'array',
      description: 'dependency-ordered layers; each layer is a list of independent ticket ids',
      items: { type: 'array', items: { type: 'string' } },
    },
    notes: { type: 'string' },
  },
}

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

// ---- argument parsing: ticket id / set, a tickets-file path, or nothing ----
const raw = typeof args === 'string' ? args.trim() : ''
const ticketsFile = raw.endsWith('.md') ? raw : 'TICKETS.md'
const only = raw && raw.split(/\s+/).every((t) => /^T\d+$/i.test(t)) ? raw.split(/\s+/).map((t) => t.toUpperCase()) : null

const context = (ticketsFile, specFile) => `Repo: the rails_mcp gem at the working-tree
root. Read ${specFile} (the contract), ${ticketsFile} (the breakdown), docs/conventions.md,
and docs/adr/. Follow the .claude/skills/spec-driven-dev skill. Never bypass the pre-commit
gate (--no-verify is denied). Only touch files your ticket owns.`

const plannerPrompt = () => `Read ${ticketsFile}. Extract every ticket: its id and its
"Depends on" list. Topologically sort them into LAYERS — layer N holds tickets whose
dependencies all appear in earlier layers; tickets in the same layer must be independent
(they own disjoint files). ${only ? `Restrict to these tickets and any of their required dependencies, preserving order: ${only.join(', ')}.` : 'Include all tickets.'} Also report the SPEC file the tickets reference (default SPEC.md if unstated). Return {tickets_file, spec_file, layers, notes}.`

const builderPrompt = (t, specFile) => `${context(ticketsFile, specFile)}

You are the builder for ticket ${t}. Do this:
1. Read ticket ${t} in ${ticketsFile}: its owned files, dependencies, referenced SPEC
   requirements, and its tag.
2. Read those requirements in ${specFile}. Their acceptance criteria are your test list.
3. If ${t} touches the MCP protocol, tool schema, Rack transport, or annotations, fetch the
   official mcp gem's current API first (context7 or its docs). Do NOT invent its API.
4. If ${t} is needs-human-oracle and a referenced OPEN: is unresolved, set status "blocked",
   put the exact question in open_questions, and do not guess the decision.
5. Otherwise: test-first. Write failing tests from the acceptance criteria (one behavior per
   test, cite the requirement id), then implement to green in ${t}'s owned files only. While
   iterating run ONLY your ticket's own test file(s) — the layer gate runs the full suite.
   Clean to docs/conventions.md.

Return the schema: work_id="${t}", status, files_touched, criteria_covered, test_names,
findings, open_questions.`

const gatePrompt = (layer, specFile) => `${context(ticketsFile, specFile)}

Layer [${layer.join(', ')}] builders just finished. Run the full mechanical gate on the
working tree: bundle exec standardrb, bundle exec rake test (full suite), and the
ADR-constraint greps in .githooks/pre-commit. Do NOT fix anything — only report. If
everything is green, stage all changes and commit "build: layer ${layer.join('+')}" (this
runs the pre-commit hook). Return the schema with work_id="layer ${layer.join('+')}",
status="pass" only if committed green, else "fail" with findings naming the failing files
and tests.`

const healPrompt = (layer, gate, specFile) => `${context(ticketsFile, specFile)}

The gate for layer [${layer.join(', ')}] failed:
${JSON.stringify(gate && gate.findings ? gate.findings : gate, null, 2)}

Fix the failures within this layer's owned files only. Re-run the failing tests/linter to
confirm. Return the schema (work_id="heal ${layer.join('+')}").`

const auditPrompt = (specFile) => `${context(ticketsFile, specFile)}

All layers are built and committed. Act as an INDEPENDENT integration auditor (you did not
write this code). Run the full suite and standardrb; confirm green. Walk ${specFile}'s
requirements and confirm each one's acceptance criteria have a passing test — list any
requirement with no covering test as a finding. Confirm the lib/ invariants hold: no
arbitrary-Ruby/console path, no gem-side policy or tenant logic, no hand-rolled JSON-RPC,
authorize fails closed, no credential in the notification payload. Report only, do not fix.
Return the schema with work_id="integration", status, findings, criteria_covered.`

const reflectPrompt = (specFile) => `${context(ticketsFile, specFile)}

The build burst is done. Review the whole diff on this branch. If it made a durable,
architecturally-significant decision not already recorded, write an ADR in docs/adr/ (use
docs/adr/_template.md; immutable-once-accepted rules). If it produced a reusable convention
or gotcha, add a line to CLAUDE.md. Record the "why" now while context is fresh. Summarize
what you recorded (or that nothing warranted it).`

const archivePrompt = (specFile) => `${context(ticketsFile, specFile)}

The build passed audit. Archive the completed build plan as a point-in-time record WITHOUT
breaking re-runs:
- Copy (do not move) ${ticketsFile} into docs/archive/<basename-without-ext>/ with a header
  noting "Completed <output of the 'date' command> at commit <git rev-parse --short HEAD>".
- In the working ${ticketsFile}, mark each delivered ticket complete (a checked box or DONE
  status). Leave ${specFile} in place as the living requirements — do not archive it.
- Confirm the generated assets exist: docs/USAGE.md, docs/SEAMS.md (if the tickets produce
  them), and docs/adr/ entries. Note any missing.
Commit "archive: build-plan snapshot on completion". Return a short summary of what was
archived and what stays living.`

// ---- run ----

phase('Plan')
const plan = await agent(plannerPrompt(), { label: 'plan', phase: 'Plan', schema: PLAN_SCHEMA })
const layers = plan && Array.isArray(plan.layers) ? plan.layers.filter((l) => l && l.length) : []
const specFile = (plan && plan.spec_file) || 'SPEC.md'
if (!layers.length) {
  log(`No tickets to build from ${ticketsFile}.`)
  return { plan }
}
log(`Plan from ${ticketsFile} (spec: ${specFile}): ${layers.length} layer(s) — ${layers.map((l) => `[${l.join(',')}]`).join(' → ')}`)

for (const layer of layers) {
  phase('Build')
  const built = (await parallel(
    layer.map((t) => () => agent(builderPrompt(t, specFile), { label: `build:${t}`, phase: 'Build', schema: RESULT_SCHEMA }))
  )).filter(Boolean)

  const blocked = built.filter((r) => r.status === 'blocked')
  if (blocked.length) {
    log(`⛔ Layer [${layer.join(', ')}] blocked on unresolved OPEN: decisions — stopping for Brandon.`)
    return { plan, stoppedAt: layer, reason: 'blocked', blocked }
  }
  log(`Layer [${layer.join(', ')}] built: ${built.filter((r) => r.status === 'pass').length}/${layer.length} builder-pass`)

  phase('Gate')
  let round = 0
  let gate = await agent(gatePrompt(layer, specFile), { label: `gate:${layer.join('+')}`, phase: 'Gate', schema: RESULT_SCHEMA })
  while ((!gate || gate.status !== 'pass') && round < 3) {
    round += 1
    await agent(healPrompt(layer, gate, specFile), { label: `heal:${layer.join('+')}#${round}`, phase: 'Gate', schema: RESULT_SCHEMA })
    gate = await agent(gatePrompt(layer, specFile), { label: `gate:${layer.join('+')}#${round}`, phase: 'Gate', schema: RESULT_SCHEMA })
  }
  if (!gate || gate.status !== 'pass') {
    log(`⚠ Layer [${layer.join(', ')}] not green after ${round} heal rounds — stopping for human review.`)
    return { plan, stoppedAt: layer, reason: 'gate-failed', gate }
  }
  log(`✓ Layer [${layer.join(', ')}] committed green.`)
}

phase('Audit')
const audit = await agent(auditPrompt(specFile), { label: 'integration-audit', phase: 'Audit', schema: RESULT_SCHEMA })

phase('Reflect')
const reflect = await agent(reflectPrompt(specFile), { label: 'reflect', phase: 'Reflect' })

phase('Archive')
const archive = await agent(archivePrompt(specFile), { label: 'archive', phase: 'Archive' })

return { plan, audit, reflect, archive }
