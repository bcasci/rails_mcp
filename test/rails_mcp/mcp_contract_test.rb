# frozen_string_literal: true

require "test_helper"
require "mcp"

# R1 (ARCH-01) — the mcp public-contract drift test. rails_mcp no longer reads
# `mcp`'s private `@input_schema_value` ivar to tell "the app set a raw input_schema"
# from "the app used only `arg`/nothing"; it tracks that in its own state. But the
# gem still relies on one `mcp` behavior: a bare `MCP::Tool` advertises an *empty*
# input schema, and a raw-set schema advertises its properties, both via the public
# `input_schema_value.to_h`. These tests pin that public contract so a future
# `bundle update mcp` that changes it fails here — a drift test, not a `~>` pin.
#
# No test here references `@input_schema_value` or any other private ivar.
class McpContractTest < Minitest::Test
  # R1: a bare `MCP::Tool` (no explicit schema) advertises an empty properties set via
  # the public `input_schema_value.to_h`. If mcp starts pre-populating properties, the
  # allow-list assumptions rails_mcp relies on break — this fails first.
  def test_bare_mcp_tool_advertises_an_empty_input_schema
    tool = Class.new(MCP::Tool) { tool_name "bare" }

    properties = tool.input_schema_value.to_h[:properties]

    assert_empty(properties || {})
  end

  # R1: a tool that raw-set a schema advertises exactly those properties via the same
  # public accessor — the escape hatch rails_mcp round-trips to `perform`.
  def test_raw_set_schema_advertises_its_properties
    tool = Class.new(MCP::Tool) do
      tool_name "raw"
      input_schema(properties: {q: {type: "string"}}, required: ["q"])
    end

    properties = tool.input_schema_value.to_h[:properties]

    assert_equal({q: {type: "string"}}, properties)
  end
end
