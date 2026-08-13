# frozen_string_literal: true

require "test_helper"

# T1 — Args DSL (R1). The DSL declares typed, named args that become the tool's
# MCP input schema; only declared args reach `perform` (allow-list on args), and
# validation delegates to the official `mcp` gem's `input_schema` (no hand-rolled
# type engine).
#
# `RailsMcp::Args` is a class-level mixin (T4's base class extends it). These tests
# exercise it in isolation on a throwaway class that extends it directly.
class ArgsTest < Minitest::Test
  def build_tool(&block)
    Class.new do
      extend RailsMcp::Args

      class_exec(&block) if block
    end
  end

  # R1: a declared `arg :household_id, :integer, required: true` becomes a required
  # integer in the tool's MCP input schema.
  def test_declared_required_integer_arg_is_a_required_integer_in_the_input_schema
    tool = build_tool { arg :household_id, :integer, required: true }

    schema = tool.input_schema.to_h

    assert_equal "integer", schema.dig(:properties, :household_id, :type)
    assert_includes schema[:required], "household_id"
  end

  # R1: an optional arg contributes a property but is not listed as required.
  def test_optional_arg_is_a_property_but_not_required
    tool = build_tool { arg :note, :string }

    schema = tool.input_schema.to_h

    assert_equal "string", schema.dig(:properties, :note, :type)
    refute_includes Array(schema[:required]), "note"
  end

  # R1: the DSL builds a real `MCP::Tool::InputSchema` — validation is delegated to
  # the official gem, not a hand-rolled type engine (R1 DECIDED).
  def test_input_schema_is_an_mcp_input_schema
    tool = build_tool { arg :household_id, :integer, required: true }

    assert_kind_of MCP::Tool::InputSchema, tool.input_schema
  end

  # R1: a missing required arg is rejected (before `perform`) via the gem's schema.
  def test_missing_required_arg_is_rejected
    tool = build_tool { arg :household_id, :integer, required: true }

    assert tool.input_schema.missing_required_arguments?({})
    refute tool.input_schema.missing_required_arguments?(household_id: 1)
  end

  # R1: a wrong-typed arg is rejected (before `perform`) via the gem's schema.
  def test_wrong_typed_arg_is_rejected
    tool = build_tool { arg :household_id, :integer, required: true }

    assert_raises(MCP::Tool::InputSchema::ValidationError) do
      tool.input_schema.validate_arguments(household_id: "not-an-integer")
    end
  end

  # R1: a correctly typed arg passes validation.
  def test_correctly_typed_arg_passes_validation
    tool = build_tool { arg :household_id, :integer, required: true }

    tool.input_schema.validate_arguments(household_id: 42) # raises on failure
  end

  # R1 (allow-list on args): undeclared args are dropped and never forwarded to
  # `perform`. The gem's JSON Schema permits extra properties, so the DSL filters.
  def test_undeclared_args_are_not_forwarded
    tool = build_tool { arg :household_id, :integer, required: true }

    filtered = tool.declared_arguments(household_id: 42, evil: "rm -rf", tenant_id: 9)

    assert_equal({household_id: 42}, filtered)
  end

  # R1: filtering accepts string keys (the wire delivers JSON string keys) and
  # returns symbol keys suitable for `perform(**args)`.
  def test_declared_arguments_accepts_string_keys
    tool = build_tool { arg :household_id, :integer, required: true }

    filtered = tool.declared_arguments("household_id" => 42, "evil" => "x")

    assert_equal({household_id: 42}, filtered)
  end

  # R1: the set of declared arg names is queryable (the allow-list surface).
  def test_declared_arg_names_are_queryable
    tool = build_tool do
      arg :household_id, :integer, required: true
      arg :note, :string
    end

    assert_equal [:household_id, :note], tool.declared_arg_names
  end

  # R1: a description passed to `arg` is carried into the schema property.
  def test_arg_description_is_carried_into_the_schema
    tool = build_tool { arg :household_id, :integer, description: "the household" }

    assert_equal "the household", tool.input_schema.to_h.dig(:properties, :household_id, :description)
  end

  # R1: subclasses inherit the parent's declared args and can add their own without
  # mutating the parent (the base class is subclassed via ApplicationMcpTool → tools).
  def test_subclasses_inherit_and_extend_declared_args_without_mutating_parent
    parent = build_tool { arg :household_id, :integer, required: true }
    child = Class.new(parent) { arg :note, :string }

    assert_equal [:household_id], parent.declared_arg_names
    assert_equal [:household_id, :note], child.declared_arg_names
  end

  # R1: an unknown type is rejected at declaration time (fail fast, not a silent
  # untyped property the AI could exploit).
  def test_unknown_type_is_rejected_at_declaration
    assert_raises(ArgumentError) do
      build_tool { arg :household_id, :not_a_real_type }
    end
  end

  # --- R1: DSL yields to an explicitly-set input_schema ------------------------
  #
  # A RailsMcp::Tool is an MCP::Tool subclass, so the raw `input_schema(...)` macro
  # from the official gem is available. These tests exercise the composition the gem
  # actually uses: a real MCP::Tool subclass with the Args mixin, so `super` reaches
  # the gem's macro.
  def build_mcp_tool(&block)
    Class.new(MCP::Tool) do
      extend RailsMcp::Args

      tool_name "demo"
      class_exec(&block) if block
    end
  end

  # R1: a tool that sets a raw `input_schema(properties:, required:)` and declares no
  # `arg` advertises the explicitly-set schema (not an empty DSL-built one). The
  # server advertises via `to_h[:inputSchema]`, so assert there.
  def test_raw_input_schema_with_no_arg_is_the_advertised_schema
    tool = build_mcp_tool do
      input_schema(properties: {q: {type: "string"}}, required: ["q"])
    end

    advertised = tool.to_h[:inputSchema]

    assert_equal({q: {type: "string"}}, advertised[:properties])
    assert_equal ["q"], advertised[:required]
  end

  # R1: a tool that uses `arg` and does not set `input_schema` still builds the schema
  # from the declared args exactly as spec 0001 R1 froze — the advertised schema (via
  # to_h) carries the declared arg.
  def test_arg_only_tool_advertises_the_dsl_built_schema
    tool = build_mcp_tool { arg :household_id, :integer, required: true }

    advertised = tool.to_h[:inputSchema]

    assert_equal "integer", advertised.dig(:properties, :household_id, :type)
    assert_includes advertised[:required], "household_id"
  end

  # R1: when a tool BOTH uses `arg` and sets a raw `input_schema`, the explicitly-set
  # schema wins (the explicit value is the escape hatch). The DSL arg does not appear.
  def test_explicit_input_schema_wins_over_arg_when_both_present
    tool = build_mcp_tool do
      arg :household_id, :integer, required: true
      input_schema(properties: {q: {type: "string"}}, required: ["q"])
    end

    advertised = tool.to_h[:inputSchema]

    assert_equal({q: {type: "string"}}, advertised[:properties])
    assert_equal ["q"], advertised[:required]
    refute_includes Array(advertised[:required]), "household_id"
  end

  # R1: the explicit schema is authoritative on the validation path too (the gem's
  # call_tool validation reads `input_schema`), so the two never fight.
  def test_input_schema_getter_returns_the_explicit_schema_when_set
    tool = build_mcp_tool do
      arg :household_id, :integer, required: true
      input_schema(properties: {q: {type: "string"}}, required: ["q"])
    end

    assert_equal({q: {type: "string"}}, tool.input_schema.to_h[:properties])
  end
end
