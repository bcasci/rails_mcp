# specs/

Each spec is **one capability** in a numbered folder, holding its requirements and its build
plan. `/implement` builds a spec; on completion the whole folder moves to `specs/archive/`,
so active and finished work never mix.

```
specs/
  0001-tool-framework/     # ACTIVE
    spec.md                #   requirements + acceptance criteria (R1, R2, …)
    tasks.md               #   build plan: tasks (T0, T1, …) with Depends-on + status
  archive/
    0001-…/                # finished specs move here, keeping their number
```

## What is one spec

One capability whose tasks depend only on each other and on already-shipped code. **Tasks
with build-time dependencies stay in the same spec** — that is what lets `/implement`'s
planner order and parallelize them in a single run. A new capability that builds on shipped
code (e.g. mutating tools, OAuth, audit) gets its **own** numbered spec. Never grow one spec
into a monolith of unrelated concepts.

## Numbering

Monotonic (`0001`, `0002`, …), the same scheme as `docs/adr/`. A number is a permanent id —
an archived spec keeps its number; the next new spec takes the next number. Numbers are
identity and rough chronology, not build order (dependencies live inside a spec's `tasks.md`).

## Lifecycle

- **Active** — a folder directly under `specs/`. `/implement 0001` builds it.
- **Done** — when its build passes the audit, the Archive phase marks the tasks complete, adds
  a completion header, and `git mv`s the folder into `specs/archive/`. History is preserved;
  re-running a finished spec means pointing `/implement` at its archived path (rare).
- The **living truth** after archival is the shipped code plus `docs/USAGE.md`,
  `docs/SEAMS.md`, and `docs/adr/` — not the archived spec.

## Not per-spec

`docs/adr/` (decisions cross-cut capabilities), `docs/conventions.md`, and generated docs
(`docs/USAGE.md`, `docs/SEAMS.md`) are project-wide and live under `docs/`, never inside a
spec folder.
