# frozen_string_literal: true

require "test_helper"
require "mcp"

# T5 / R10 — the registry is the allow-list surface: the only callable tools are
# the ones registered on it. These tests use a real MCP::Tool subclass (the same
# contract a RailsMcp::Tool satisfies) rather than a stub, per conventions.
class RailsMcp::RegistryTest < Minitest::Test
  def setup
    @registry = RailsMcp::Registry.new
    @tool = Class.new(MCP::Tool) do
      tool_name "example_read_only"
      def self.call(**_args)
        MCP::Tool::Response.new([{type: "text", text: "ok"}])
      end
    end
  end

  # R10: a registered tool is part of the callable surface.
  def test_register_adds_tool_to_the_set
    @registry.register(@tool)

    assert_includes @registry.tools, @tool
  end

  # R10: registration is the allow-list — an unregistered tool is not in the set.
  def test_unregistered_tool_is_not_in_the_set
    refute @registry.registered?(@tool)
    refute_includes @registry.tools, @tool
  end

  # R10: registered? reports membership.
  def test_registered_predicate_reflects_membership
    @registry.register(@tool)

    assert @registry.registered?(@tool)
  end

  # R10: the surface is a set — registering the same tool twice does not duplicate it.
  def test_registering_the_same_tool_twice_is_idempotent
    @registry.register(@tool)
    @registry.register(@tool)

    assert_equal 1, @registry.tools.count { |t| t == @tool }
  end

  # R10: clear empties the allow-list.
  def test_clear_removes_all_registered_tools
    @registry.register(@tool)
    @registry.clear

    assert_empty @registry.tools
    refute @registry.registered?(@tool)
  end

  # R10: register returns the tool so `register MyTool` reads as a declaration.
  def test_register_returns_the_tool
    assert_equal @tool, @registry.register(@tool)
  end

  # R10: a fresh registry is empty — nothing is callable until explicitly registered.
  def test_new_registry_is_empty
    assert_empty @registry.tools
  end

  # R10: there is a process-wide default registry the mount helper reads.
  def test_default_registry_is_a_registry
    assert_instance_of RailsMcp::Registry, RailsMcp.registry
  end
end
