#!/bin/bash
# Stop hook: one-shot NUDGE to record a durable decision (ADR) or learning.
# It does NOT reflect — the live model holds the session context a script can't.
# It bounces control back via a Stop `block` decision so the model decides whether
# this session produced something worth recording, and files it itself.
#
# Exit 0 + JSON `{"decision":"block","reason":…}` (NOT exit 2 — exit 2 is the error
# channel and surfaces a spurious "Stop hook error"). The block-and-continue is
# interactive-only by construction: headless/workflow runs have no live loop to
# receive it (the build workflow's own reflect stage covers those).
#
# Guards (fail-safe, never nag, never loop):
#   - stop_hook_active: already inside a continuation → pass through (no loop).
#   - once-per-session marker: nudge at most once per session.
#   - skip-if-touched: if docs/adr/ or CLAUDE.md already changed this session, the
#     record was already fed — stay quiet.

set -uo pipefail

INPUT=$(cat)

# Already continuing from a stop-hook block — allow stop (prevents infinite loop).
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  exit 0
fi

# Stable per-session id (session_id, else sanitized transcript_path, else unknown).
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
if [ -z "$SESSION_ID" ]; then
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$TRANSCRIPT" ]; then
    SESSION_ID=$(echo "$TRANSCRIPT" | tr -c '[:alnum:]' '_')
  else
    SESSION_ID="unknown"
  fi
fi
MARKER="/tmp/.rails-mcp-adr-nudged-${SESSION_ID}"

# Already nudged this session — allow stop (once per session).
[ -f "$MARKER" ] && exit 0

# Detect base branch (don't hardcode main); fall back to main. Guard git so a
# non-repo / missing base fails safe.
BASE_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
[ -z "$BASE_BRANCH" ] && BASE_BRANCH="main"

# Skip-if-touched: a record was already fed this session → stay quiet.
touched() {
  git diff --name-only 2>/dev/null | grep -qE "$1" \
    || git diff --cached --name-only 2>/dev/null | grep -qE "$1" \
    || git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null | grep -qE "$1"
}
if touched '^docs/adr/' || touched '^CLAUDE\.md$'; then
  exit 0
fi

# First nudge this session — block once, mark, hand control to the model.
touch "$MARKER"
NUDGE=$(cat <<'NUDGE'
Before stopping: did this session make a durable decision or produce a reusable learning
NOT already recorded?

- An architecturally significant, hard-to-reverse DECISION (a new/replaced dependency, a
  changed public seam — authorize, the notification payload, mount_mcp — a structural
  choice): write an ADR in docs/adr/ using the Nygard template, at decision time.
- A reusable CONVENTION or gotcha for this gem: add a line to CLAUDE.md.
- A cross-project or behavioral learning: save it to your user-local memory.

If none apply (a one-off, a personal preference, or already recorded): just stop again.
NUDGE
)
jq -n --arg reason "$NUDGE" '{decision: "block", reason: $reason}'
exit 0
