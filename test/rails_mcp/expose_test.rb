# frozen_string_literal: true

require "test_helper"
require "mcp"

# T1 / R3, R5 — `expose!` is an optional co-located registration macro: a tool
# registers itself on the process-wide `RailsMcp.registry` from inside its own
# class body, with no initializer entry. It is explicit and idempotent, and the
# gem still never auto-registers a tool by mere subclassing (no auto-discovery).
class RailsMcp::ExposeTest < Minitest::Test
  def setup
    # The macro targets the shared default registry; isolate each test from it.
    RailsMcp.registry.clear
  end

  def teardown
    RailsMcp.registry.clear
  end

  # R3: `expose!` puts the tool on `RailsMcp.registry` with no initializer entry —
  # co-located self-registration from inside the class.
  def test_expose_self_registers_on_the_default_registry
    klass = Class.new(RailsMcp::Tool) do
      tool_name "exposed"
      expose!
    end

    assert RailsMcp.registry.registered?(klass)
    assert_includes RailsMcp.registry.tools, klass
  end

  # R3: an exposed tool is listable/callable — it is part of the served surface
  # exactly as a centrally-registered tool would be.
  def test_exposed_tool_is_listable
    klass = Class.new(RailsMcp::Tool) do
      tool_name "listable"
      expose!
    end

    assert_includes RailsMcp.registry.tools, klass
  end

  # R3: `expose!` is idempotent (like `register`) — calling it twice (e.g. a
  # reload re-running the class body) leaves the tool on the registry once.
  def test_expose_is_idempotent
    klass = Class.new(RailsMcp::Tool) do
      tool_name "twice"
      expose!
      expose!
    end

    assert_equal 1, RailsMcp.registry.tools.count { |t| t == klass }
  end

  # R5: a `RailsMcp::Tool` subclass that never calls `expose!` (nor is registered)
  # is absent from the registry — the gem does not auto-register by subclassing.
  def test_unexposed_subclass_is_absent_from_the_registry
    klass = Class.new(RailsMcp::Tool) do
      tool_name "unexposed"
    end

    refute RailsMcp.registry.registered?(klass)
    refute_includes RailsMcp.registry.tools, klass
  end

  # R5: defining a subclass has no side effect on the registry at all — no
  # `inherited`-hook auto-discovery. The registry stays empty until an explicit act.
  def test_defining_a_subclass_does_not_touch_the_registry
    Class.new(RailsMcp::Tool) { tool_name "silent" }

    assert_empty RailsMcp.registry.tools
  end

  # R3: `expose!` returns the tool class so it reads as a declaration and can be
  # used inline.
  def test_expose_returns_the_tool_class
    klass = nil
    defined = Class.new(RailsMcp::Tool) do
      tool_name "returns_self"
      klass = expose!
    end

    assert_same defined, klass
  end
end
