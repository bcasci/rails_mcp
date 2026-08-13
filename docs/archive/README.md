# docs/archive/

Point-in-time snapshots of completed build plans.

## Lifecycle

- **`SPEC.md`** is the *living* requirements — what the gem does. It is never archived; it
  is updated as the gem evolves.
- **A tickets file** (e.g. `TICKETS.md`) is a *one-time build plan*. When `/implement`
  finishes a build and passes the audit, its Archive phase copies the tickets file here as
  `docs/archive/<name>/<name>.md` with a completion header (date + commit), and marks the
  working tickets file done. The working copy stays in place so a build can be re-run.
- **ADRs** (`docs/adr/`) are the permanent decision log. **Generated docs**
  (`docs/USAGE.md`, `docs/SEAMS.md`) are living. Neither is archived here.

## Future changes (post-v1)

For ongoing evolution — a v2 spec, phase-2 mutations — write a new tickets file (and, if the
requirements change, a new or amended `SPEC.md` section), run `/implement <that file>`, and
it archives on completion. When change proposals become frequent, adopt an OpenSpec-style
`changes/ → archive/` flow; until then, one living `SPEC.md` plus archived build plans is
enough.
