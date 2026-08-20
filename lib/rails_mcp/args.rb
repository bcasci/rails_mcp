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
      @built_input_schema = nil # invalidate the memoized DSL-built schema; args changed
    end

    # The declared arg names, in declaration order — the allow-list surface.
    def declared_arg_names
      arg_definitions.keys
    end

    # The tool's MCP input schema (R1). Two roles, so the DSL yields to an
    # explicitly-set value rather than caging the tool into the `arg` DSL:
    #
    #   input_schema(properties:, required:)  # setter — an explicit raw schema
    #   input_schema                          # getter — the advertised schema
    #
    # As a setter it delegates to the official gem's `input_schema` macro (the tool
    # is an `MCP::Tool`), recording an explicit value, and records rails_mcp's own
    # `@explicit_input_schema = true` flag so the distinction rests on rails_mcp state,
    # not on `mcp`'s private schema ivar (ARCH-01). As a getter it
    # returns that explicit value when one was set; otherwise it builds the schema
    # from the declared `arg`s (spec 0001 R1, unchanged). An explicit schema wins over
    # `arg` — the explicit value is the escape hatch (R1 DECIDED, ADR-0007).
    def input_schema(*args)
      unless args.empty? # setter → the gem's macro sets the explicit value
        @explicit_input_schema = true
        return super
      end

      explicitly_set_input_schema? ? super : built_input_schema
    end

    # The value the official gem advertises via `to_h` and reads on the call path.
    # Overridden so a `RailsMcp::Tool` advertises the same schema the getter returns:
    # the explicit value when set, else the `arg`-built one. Without this override the
    # gem would advertise an empty schema for an `arg`-only tool (`to_h` reads
    # `input_schema_value`, not `input_schema`).
    def input_schema_value
      return super if explicitly_set_input_schema? || arg_definitions.empty?

      built_input_schema
    end

    # The allow-list `declared_arguments` filters against: the tool's **effective**
    # input schema's property keys, not only its `arg` declarations (ARCH-02). When a
    # tool set a raw `input_schema`, the allow-list is that schema's `properties` keys
    # (as symbols) so the tool round-trips its declared properties to `perform`;
    # otherwise it is the `arg`-declared names. Undeclared args are dropped either way.
    def effective_arg_names
      if explicitly_set_input_schema?
        (input_schema.to_h[:properties] || {}).keys.map(&:to_sym)
      else
        declared_arg_names
      end
    end

    # Filter incoming arguments to only the effective-schema ones, returning a
    # symbol-keyed hash suitable for `perform(**args)`. Undeclared args are dropped so
    # the AI can never smuggle an argument the tool did not declare (R1 allow-list on
    # args). Accepts string or symbol keys (the wire delivers JSON string keys).
    def declared_arguments(arguments)
      names = effective_arg_names
      arguments.each_with_object({}) do |(key, value), kept|
        name = key.to_sym
        kept[name] = value if names.include?(name)
      end
    end

    private

    # True when the tool set a raw schema via the `input_schema(...)` macro. Reads
    # rails_mcp's own `@explicit_input_schema` flag, set by the setter override, rather
    # than `mcp`'s private schema ivar (ARCH-01) — the distinction the
    # gem needs is not expressible through `mcp`'s public surface, so rails_mcp tracks
    # it in its own state. The R1 drift test pins the public `mcp` behavior relied on.
    def explicitly_set_input_schema?
      @explicit_input_schema == true
    end

    # The `MCP::Tool::InputSchema` built from the declared `arg`s. Memoized; the memo
    # is invalidated whenever a new `arg` is declared.
    #
    # Memo invariant (ARCH-05): the class-level DSL calls — `arg`, `read_only!`, and
    # the `input_schema` setter — run at class-definition/boot time only. They are the
    # only writers of the memoized `@built_input_schema` / `@arg_definitions` (and the
    # `@explicit_input_schema` flag). The memo's thread-safety relies on those writes
    # completing before any concurrent request-time read; do not mutate this class
    # state at request time.
    def built_input_schema
      @built_input_schema ||= begin
        properties = {}
        required = []
        arg_definitions.each do |name, definition|
          properties[name] = definition[:property]
          required << name.to_s if definition[:required]
        end
        MCP::Tool::InputSchema.new(properties: properties, required: required)
      end
    end

    # Per-class arg registry, seeded from the superclass so subclasses inherit the
    # parent's declared args and extend them without mutating the parent.
    def arg_definitions
      @arg_definitions ||=
        if superclass.respond_to?(:arg_definitions, true)
          superclass.__send__(:arg_definitions).dup
        else
          {}
        end
    end
  end
end
