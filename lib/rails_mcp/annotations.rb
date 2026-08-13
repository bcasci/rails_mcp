# frozen_string_literal: true

module RailsMcp
  # Class-level DSL for a tool's MCP annotation tier. Mixed into RailsMcp::Tool
  # (which subclasses MCP::Tool); the annotations reach the client through the
  # official gem's `annotations` mechanism — the gem serializes them, we do not
  # hand-roll the hints (ADR-0001).
  #
  # `read_only!` is an optional, advisory tier a tool MAY declare (ADR-0012).
  # Annotations are advisory: they are hints the client MAY honor, never a
  # server-side gate. There is no tier enforcement; the gem does not gate
  # mutations — a write tool simply omits `read_only!`.
  #
  # Default is maximally dangerous: a tool that declares no tier is NOT treated
  # as read-only. That falls straight out of the official gem's Annotations
  # defaults (`read_only_hint: false`, `destructive_hint: true`), so an
  # unannotated tool advertises no readOnlyHint at all — the client must assume
  # the worst rather than a silent read-only.
  module Annotations
    # Declare the tool read-only: advertises `readOnlyHint: true` (and, since a
    # read-only tool cannot mutate, clears the dangerous default `destructiveHint`).
    # Delegates to the official gem's class-level `annotations` DSL.
    def read_only!
      annotations(read_only_hint: true, destructive_hint: false)
    end
  end
end
