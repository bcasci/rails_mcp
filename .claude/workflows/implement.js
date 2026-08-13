export const meta = {
  name: 'implement',
  description:
    'Spec-driven factory build. A planner resolves a spec folder under specs/ (its spec.md + tasks.md), derives the dependency-ordered build layers from tasks.md, then builder agents implement each task test-first, with a per-layer gate + heal loop, an integration audit, a reflect stage, and an archive that moves the completed spec to specs/archive/. Pass nothing to build the single active spec; a spec number/slug ("0001"); a task subset ("0001 T3 T4"); or a path to another spec\'s tasks.md.',
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
  required: ['spec_dir', 'spec_file', 'tasks_file', 'layers'],
  properties: {
    spec_dir: { type: 'string', description: 'the resolved spec folder, e.g. specs/0001-tool-framework' },
    spec_file: { type: 'string', description: 'path to that spec\'s spec.md' },
    tasks_file: { type: 'string', description: 'path to that spec\'s tasks.md' },
    layers: {
      type: 'array',
      description: 'dependency-ordered layers; each layer is a list of independent task ids',
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
    work_id: { type: 'string', description: 'task id (e.g. T3), a layer label, or "integration"' },
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
      description: 'unresolved OPEN: forks that need Brandon before this task can finish',
    },
  },
}

const raw = typeof args === 'string' ? args.trim() : ''

const context = (specFile, tasksFile) => `Repo: the rails_mcp gem at the working-tree root.
This build is for the spec at ${specFile} with the plan at ${tasksFile}. Read those, plus
docs/conventions.md and docs/adr/. Follow the .claude/skills/spec-driven-dev skill. Never
bypass the pre-commit gate (--no-verify is denied). Only touch files your task owns.`

const plannerPrompt = () => `Resolve which spec to build from this argument: "${raw}".
Rules:
- Empty → the single ACTIVE spec folder directly under specs/ (exclude specs/archive/). If
  there is more than one active spec and no argument, return layers: [] and explain in notes.
- A number or slug (e.g. "0001" or "0001-tool-framework") → the matching specs/<dir>/.
- A path to a tasks.md → that spec.
- Trailing task ids (e.g. "0001 T3 T4") → restrict to those tasks plus any of their required
  dependencies.
Then read that spec's tasks.md, extract each task's id and "Depends on" list, and
topologically sort into LAYERS (layer N holds tasks whose dependencies are all in earlier
layers; tasks in a layer are independent and own disjoint files). Return {spec_dir,
spec_file, tasks_file, layers, notes}. spec_file is the spec.md in the folder.`

const builderPrompt = (t, specFile, tasksFile) => `${context(specFile, tasksFile)}

You are the builder for task ${t}. Do this:
1. Read task ${t} in ${tasksFile}: its owned files, dependencies, referenced spec
   requirements, and its tag.
2. Read those requirements in ${specFile}. Their acceptance criteria are your test list.
3. If ${t} touches the MCP protocol, tool schema, Rack transport, or annotations, fetch the
   official mcp gem's current API first (context7 or its docs). Do NOT invent its API.
4. If ${t} is needs-human-oracle and a referenced OPEN: is unresolved, set status "blocked",
   put the exact question in open_questions, and do not guess the decision.
5. Otherwise: test-first. Write failing tests from the acceptance criteria (one behavior per
   test, cite the requirement id), then implement to green in ${t}'s owned files only. While
   iterating run ONLY your task's own test file(s) — the layer gate runs the full suite.
   Clean to docs/conventions.md.

Return the schema: work_id="${t}", status, files_touched, criteria_covered, test_names,
findings, open_questions.`

const gatePrompt = (layer, specFile, tasksFile) => `${context(specFile, tasksFile)}

Layer [${layer.join(', ')}] builders just finished. Run the full mechanical gate on the
working tree: bundle exec standardrb, bundle exec rake test (full suite), and the
ADR-constraint greps in .githooks/pre-commit. Do NOT fix anything — only report. If
everything is green, stage all changes and commit "build: layer ${layer.join('+')}" (this
runs the pre-commit hook). Return the schema with work_id="layer ${layer.join('+')}",
status="pass" only if committed green, else "fail" with findings naming the failing files
and tests.`

const healPrompt = (layer, gate, specFile, tasksFile) => `${context(specFile, tasksFile)}

The gate for layer [${layer.join(', ')}] failed:
${JSON.stringify(gate && gate.findings ? gate.findings : gate, null, 2)}

Fix the failures within this layer's owned files only. Re-run the failing tests/linter to
confirm. Return the schema (work_id="heal ${layer.join('+')}").`

const auditPrompt = (specFile, tasksFile) => `${context(specFile, tasksFile)}

All layers are built and committed. Act as an INDEPENDENT integration auditor (you did not
write this code). Run the full suite and standardrb; confirm green. Walk ${specFile}'s
requirements and confirm each one's acceptance criteria have a passing test — list any
requirement with no covering test as a finding. Confirm the lib/ invariants hold: no
arbitrary-Ruby/console path, no gem-side policy or tenant logic, no hand-rolled JSON-RPC,
authorize fails closed, no credential in the notification payload. Report only, do not fix.
Return the schema with work_id="integration", status, findings, criteria_covered.`

const reflectPrompt = (specFile, tasksFile) => `${context(specFile, tasksFile)}

The build burst is done. Review the whole diff on this branch. If it made a durable,
architecturally-significant decision not already recorded, write an ADR in docs/adr/ (use
docs/adr/_template.md; immutable-once-accepted rules). If it produced a reusable convention
or gotcha, add a line to CLAUDE.md. Record the "why" now while context is fresh. Summarize
what you recorded (or that nothing warranted it).`

const archivePrompt = (specDir, specFile, tasksFile) => `${context(specFile, tasksFile)}

The build passed audit. Archive the completed spec so active and done specs don't mix:
- In ${tasksFile}, mark each delivered task complete (checked box or DONE status) and add a
  header "Completed <output of the 'date' command> at commit <git rev-parse --short HEAD>".
- Then MOVE the whole spec folder into specs/archive/ with git:
  git mv ${specDir} specs/archive/<basename of ${specDir}>  (create specs/archive/ if absent).
  The number stays in the name. The spec is done; the living truth is now the shipped code,
  docs/USAGE.md, docs/SEAMS.md, and docs/adr/.
- Confirm those generated docs exist; note any missing.
Commit "archive: move completed <basename> to specs/archive/". Return a short summary.`

// ---- run ----

phase('Plan')
const plan = await agent(plannerPrompt(), { label: 'plan', phase: 'Plan', schema: PLAN_SCHEMA })
const layers = plan && Array.isArray(plan.layers) ? plan.layers.filter((l) => l && l.length) : []
const specFile = (plan && plan.spec_file) || 'spec.md'
const tasksFile = (plan && plan.tasks_file) || 'tasks.md'
const specDir = (plan && plan.spec_dir) || ''
if (!layers.length) {
  log(`No tasks to build${plan && plan.notes ? ` — ${plan.notes}` : ''}.`)
  return { plan }
}
log(`Plan: ${specDir} — ${layers.length} layer(s): ${layers.map((l) => `[${l.join(',')}]`).join(' → ')}`)

for (const layer of layers) {
  phase('Build')
  const built = (await parallel(
    layer.map((t) => () => agent(builderPrompt(t, specFile, tasksFile), { label: `build:${t}`, phase: 'Build', schema: RESULT_SCHEMA }))
  )).filter(Boolean)

  const blocked = built.filter((r) => r.status === 'blocked')
  if (blocked.length) {
    log(`⛔ Layer [${layer.join(', ')}] blocked on unresolved OPEN: decisions — stopping for Brandon.`)
    return { plan, stoppedAt: layer, reason: 'blocked', blocked }
  }
  log(`Layer [${layer.join(', ')}] built: ${built.filter((r) => r.status === 'pass').length}/${layer.length} builder-pass`)

  phase('Gate')
  let round = 0
  let gate = await agent(gatePrompt(layer, specFile, tasksFile), { label: `gate:${layer.join('+')}`, phase: 'Gate', schema: RESULT_SCHEMA })
  while ((!gate || gate.status !== 'pass') && round < 3) {
    round += 1
    await agent(healPrompt(layer, gate, specFile, tasksFile), { label: `heal:${layer.join('+')}#${round}`, phase: 'Gate', schema: RESULT_SCHEMA })
    gate = await agent(gatePrompt(layer, specFile, tasksFile), { label: `gate:${layer.join('+')}#${round}`, phase: 'Gate', schema: RESULT_SCHEMA })
  }
  if (!gate || gate.status !== 'pass') {
    log(`⚠ Layer [${layer.join(', ')}] not green after ${round} heal rounds — stopping for human review.`)
    return { plan, stoppedAt: layer, reason: 'gate-failed', gate }
  }
  log(`✓ Layer [${layer.join(', ')}] committed green.`)
}

phase('Audit')
const audit = await agent(auditPrompt(specFile, tasksFile), { label: 'integration-audit', phase: 'Audit', schema: RESULT_SCHEMA })

phase('Reflect')
const reflect = await agent(reflectPrompt(specFile, tasksFile), { label: 'reflect', phase: 'Reflect' })

phase('Archive')
const archive = await agent(archivePrompt(specDir, specFile, tasksFile), { label: 'archive', phase: 'Archive' })

return { plan, audit, reflect, archive }
