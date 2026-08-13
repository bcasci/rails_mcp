# frozen_string_literal: true

require "mcp"

module RailsMcp
  # The args DSL (R1). A class-level mixin: the tool base class (T4) extends it so a
  # tool declares typed, named arguments with `arg`. Each declared arg becomes part
  # of the tool's MCP input schema, and only declared args reach `perform` — the AI
  # cannot pass arbitrary arguments (allow-list on args).
  #
  # Validation is delegated to the official `mcp` gem: `arg` builds an
  # `MCP::Tool::InputSchema`, and the gem validates required-ness and type against it
  # (R1 DECIDED — no hand-rolled type engine). The DSL adds the one thing the JSON
  # Schema does not enforce by default: dropping undeclared arguments.
  module Args
    # Maps the DSL's domain-friendly type names to JSON Schema types. A type absent
    # here is rejected at declaration time rather than becoming an untyped property.
    TYPES = {
      string: "string",
      integer: "integer",
      number: "number",
      boolean: "boolean",
      array: "array",
      object: "object"
    }.freeze

    # Declare a named, typed argument.
    #
    #   arg :household_id, :integer, required: true, description: "the household"
    #
    # The arg name is what the AI sees in the schema; name it for the domain concept.
    def arg(name, type, required: false, description: nil)
      json_type = TYPES.fetch(type) do
        raise ArgumentError,
          "unknown arg type #{type.inspect} for #{name.inspect}; known types: #{TYPES.keys.join(", ")}"
      end

      property = {type: json_type}
      property[:description] = description if description

      arg_definitions[name.to_sym] = {property: property, required: required}
      @input_schema = nil # invalidate the memoized schema; args changed
    end

    # The declared arg names, in declaration order — the allow-list surface.
    def declared_arg_names
      arg_definitions.keys
    end

    # The tool's MCP input schema, built from the declared args. An
    # `MCP::Tool::InputSchema` so the official gem owns required/type validation.
    def input_schema
      @input_schema ||= begin
        properties = {}
        required = []
        arg_definitions.each do |name, definition|
          properties[name] = definition[:property]
          required << name.to_s if definition[:required]
        end
        MCP::Tool::InputSchema.new(properties: properties, required: required)
      end
    end

    # Filter incoming arguments to only the declared ones, returning a symbol-keyed
    # hash suitable for `perform(**args)`. Undeclared args are dropped so the AI can
    # never smuggle an argument the tool did not declare (R1 allow-list on args).
    # Accepts string or symbol keys (the wire delivers JSON string keys).
    def declared_arguments(arguments)
      names = declared_arg_names
      arguments.each_with_object({}) do |(key, value), kept|
        name = key.to_sym
        kept[name] = value if names.include?(name)
      end
    end

    private

    # Per-class arg registry, seeded from the superclass so subclasses inherit the
    # parent's declared args and extend them without mutating the parent.
    def arg_definitions
      @arg_definitions ||=
        if superclass.respond_to?(:arg_definitions, true)
          superclass.send(:arg_definitions).dup
        else
          {}
        end
    end
  end
end
