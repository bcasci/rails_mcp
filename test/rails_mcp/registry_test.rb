# frozen_string_literal: true

require "test_helper"
require "mcp"

# R10 / R1 — the registry is the allow-list surface: the only callable tools are
# the ones registered on it, keyed by `tool_name` (ADR-0009). These tests use real
# MCP::Tool subclasses (the same contract a RailsMcp::Tool satisfies) rather than a
# stub, per conventions.
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

  # Build a named tool class (Zeitwerk-loaded tools always have a real class name);
  # the constant assignment gives an anonymous class its `.name`.
  def named_tool_class(const_name, name_value)
    klass = Class.new(MCP::Tool) do
      tool_name name_value
      def self.call(**_args)
        MCP::Tool::Response.new([{type: "text", text: "ok"}])
      end
    end
    Object.const_set(const_name, klass) unless Object.const_defined?(const_name)
    Object.const_get(const_name)
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

  # R1: the same class registered twice appears once (idempotent).
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

  # R1: reload case — a redefined class (new object, same class name, same
  # tool_name) does not cause ToolNotUnique when the server is built, and the tool
  # is listed exactly once.
  def test_reload_of_a_redefined_class_builds_server_without_tool_not_unique
    original = Class.new(MCP::Tool) do
      tool_name "foo_bar"
      def self.name = "Foo::BarTool"
      def self.call(**_args) = MCP::Tool::Response.new([{type: "text", text: "ok"}])
    end
    redefined = Class.new(MCP::Tool) do
      tool_name "foo_bar"
      def self.name = "Foo::BarTool"
      def self.call(**_args) = MCP::Tool::Response.new([{type: "text", text: "ok"}])
    end

    @registry.register(original)
    @registry.register(redefined)

    server = MCP::Server.new(tools: @registry.tools)

    assert_equal 1, @registry.tools.length
    assert_equal 1, @registry.tools.count { |t| t.tool_name == "foo_bar" }
    refute_nil server
  end

  # R1: reload case — the redefined (fresh) class replaces the stale one.
  def test_reload_replaces_the_stale_class_with_the_redefined_one
    original = Class.new(MCP::Tool) do
      tool_name "foo_bar"
      def self.name = "Foo::BarTool"
    end
    redefined = Class.new(MCP::Tool) do
      tool_name "foo_bar"
      def self.name = "Foo::BarTool"
    end

    @registry.register(original)
    @registry.register(redefined)

    assert_includes @registry.tools, redefined
    refute_includes @registry.tools, original
  end

  # R1: genuine collision — two different classes (different class names) claiming
  # the same tool_name raises ToolNameCollision, naming both classes.
  def test_different_class_on_a_taken_tool_name_raises_collision
    a = Class.new(MCP::Tool) do
      tool_name "dup"
      def self.name = "Alpha::DupTool"
    end
    b = Class.new(MCP::Tool) do
      tool_name "dup"
      def self.name = "Beta::DupTool"
    end

    @registry.register(a)
    error = assert_raises(RailsMcp::ToolNameCollision) do
      @registry.register(b)
    end

    assert_includes error.message, "Alpha::DupTool"
    assert_includes error.message, "Beta::DupTool"
    assert_includes error.message, "dup"
  end

  # R1: after a collision is raised, the originally-registered class is untouched.
  def test_collision_leaves_the_first_registration_intact
    a = Class.new(MCP::Tool) do
      tool_name "dup"
      def self.name = "Alpha::DupTool"
    end
    b = Class.new(MCP::Tool) do
      tool_name "dup"
      def self.name = "Beta::DupTool"
    end

    @registry.register(a)
    assert_raises(RailsMcp::ToolNameCollision) { @registry.register(b) }

    assert_equal [a], @registry.tools
  end

  # R1: insertion order is preserved for distinct tools.
  def test_insertion_order_is_preserved_for_distinct_tools
    first = named_tool_class(:RegistryOrderFirstTool, "order_first")
    second = named_tool_class(:RegistryOrderSecondTool, "order_second")

    @registry.register(first)
    @registry.register(second)

    assert_equal [first, second], @registry.tools
  end

  # R1: a raw MCP::Tool (spec 0004 R4) keys by its tool_name the same way — a
  # redefined raw tool with the same tool_name replaces rather than duplicating.
  def test_raw_mcp_tool_keys_by_tool_name
    raw = Class.new(MCP::Tool) do
      tool_name "raw_read"
      def self.name = "RawReadTool"
      def self.call(**_args) = MCP::Tool::Response.new([{type: "text", text: "ok"}])
    end
    raw_reloaded = Class.new(MCP::Tool) do
      tool_name "raw_read"
      def self.name = "RawReadTool"
      def self.call(**_args) = MCP::Tool::Response.new([{type: "text", text: "ok"}])
    end

    @registry.register(raw)
    @registry.register(raw_reloaded)

    assert_equal 1, @registry.tools.length
    assert @registry.registered?(raw_reloaded)
  end

  # R1: registered? is answered by tool_name — a reloaded class reports registered.
  def test_registered_predicate_answered_by_tool_name
    original = Class.new(MCP::Tool) do
      tool_name "predicate_tool"
      def self.name = "PredicateTool"
    end
    reloaded = Class.new(MCP::Tool) do
      tool_name "predicate_tool"
      def self.name = "PredicateTool"
    end

    @registry.register(original)

    assert @registry.registered?(reloaded)
  end
end
