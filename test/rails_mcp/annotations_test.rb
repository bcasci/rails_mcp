# frozen_string_literal: true

require "test_helper"
require "mcp"

# T2 — Annotations DSL (SPEC R5). read_only! flows through to the official mcp
# gem's annotation surface; an unannotated tool stays maximally dangerous.
#
# The module is designed to mix into RailsMcp::Tool (a MCP::Tool subclass, built
# in T4). To test it in isolation without T4's file, we exercise it on a bare
# MCP::Tool subclass that includes the module — the exact composition T4 wires.
class RailsMcp::AnnotationsTest < Minitest::Test
  def tool_class
    Class.new(MCP::Tool) { extend RailsMcp::Annotations }
  end

  # R5: a tool that calls read_only! advertises readOnlyHint: true.
  def test_read_only_sets_read_only_hint_true
    klass = tool_class
    klass.read_only!

    assert_equal true, klass.to_h[:annotations][:readOnlyHint]
  end

  # R5: read_only! means read-only, so it must clear the maximally-dangerous
  # destructive default rather than advertise a read-only-yet-destructive tool.
  def test_read_only_clears_destructive_hint
    klass = tool_class
    klass.read_only!

    assert_equal false, klass.to_h[:annotations][:destructiveHint]
  end

  # R5: no annotation => not treated as read-only (maximally dangerous default).
  def test_unannotated_tool_is_not_read_only
    klass = tool_class

    refute_equal true, klass.to_h.dig(:annotations, :readOnlyHint)
  end

  # R5: annotations are advisory hints emitted to the client — the tier lives in
  # the tool's advertised `annotations`, not applied as a server-side gate. The
  # DSL's job is only to surface the hint in to_h, which the two tests above cover.
end
