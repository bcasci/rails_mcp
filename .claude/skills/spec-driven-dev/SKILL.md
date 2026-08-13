---
name: spec-driven-dev
description: Build a rails_mcp gem task the spec-driven, test-first way. Use whenever writing or changing rails_mcp code — implementing a tasks.md task, adding or editing a RailsMcp tool, seam, or DSL, or turning a SPEC requirement into tests and code. Walks the loop: read the task and its SPEC acceptance criteria, fetch the official mcp gem API before coding, write failing tests, implement to green, run the pre-commit gate, check the definition of done. Trigger phrases include "implement T3", "build the args DSL", "work the task", "add a test for R4", "write the tool", "spec-driven".
---

# Spec-driven development — the rails_mcp build loop

Every unit of work is a `tasks.md` task implemented against `spec.md` acceptance
criteria. The SPEC is the source of truth: tests come from its Given/When/Then, code comes
after.

## Before writing code

1. Read the task in `tasks.md` — its owned files, dependencies, and referenced SPEC
   requirements (e.g. R3).
2. Read those requirements in `spec.md`. The acceptance criteria are your test list. Note
   any `DECIDED`/`OPEN:` markers on them.
3. Read `docs/conventions.md` (naming, invariants, layout).
4. If the task touches the MCP protocol, tool schema, Rack transport, or annotations,
   **fetch the official `mcp` gem's current API first** (context7 or its docs). Do not
   invent its API — it is a real dependency. If relevant, verify the version question in
   SPEC R5 (does the pinned `mcp` emit annotations).
5. If a referenced `OPEN:` is unresolved and the task is `needs-human-oracle`, surface it
   (set status `blocked`, list it) rather than picking silently.

## The loop — test-first, heal to green

1. **Red** — translate each acceptance criterion into a failing test. One behavior per test;
   name the test for the behavior; cite the requirement id in a comment. See
   `references/testing.md` for where tests live and how to avoid duplicate coverage.
2. **Green** — write the minimum code to pass. Stay inside the task's owned files; never
   edit another task's files (disjoint ownership is what lets the fleet run in parallel).
3. **Refactor** — clean to `docs/conventions.md` while green.
4. **Gate** — while iterating, run only your task's own test file (the layer gate runs the
   full suite). Fix failures; repeat until your tests pass. Never bypass the gate
   (`--no-verify` is denied).

## Definition of done

- Every referenced acceptance criterion has a passing test.
- Your task's own tests pass; standardrb is clean; no ADR-constraint violation.
- Only the task's owned files changed.
- If the task froze a contract (a seam signature, the event name/payload), it matches SPEC
  and is noted for the docs tasks (T8).
- An ADR/learning was recorded if a durable decision was made (see `CLAUDE.md`).

## Then review — a different agent, never self-certify

Review is a separate pass. Run `/code-review --fix` (guided by `REVIEW.md`), address its
findings, and re-run the gate. Do not bless your own work.
