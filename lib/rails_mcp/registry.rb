# frozen_string_literal: true

module RailsMcp
  # Raised when two *different* tool classes claim the same `tool_name` (ADR-0009).
  # This is a genuine collision — an integrity error in the allow-list itself — not
  # a Zeitwerk reload (same class name, new object), which replaces silently. The
  # message names both colliding classes and the shared `tool_name`.
  class ToolNameCollision < Error
    def initialize(tool_name, existing_class, incoming_class)
      super(
        "tool_name #{tool_name.inspect} is already claimed by #{class_label(existing_class)}; " \
        "#{class_label(incoming_class)} cannot claim it. Give one of them a distinct tool_name."
      )
    end

    private

    def class_label(tool_class)
      tool_class.name || tool_class.inspect
    end
  end

  # The allow-list surface (SPEC R10). The only tools an AI client can list or call
  # are the ones registered here; there is no generic executor and no console tool.
  # A registry holds registered tool classes (`RailsMcp::Tool` subclasses, or any
  # `MCP::Tool`); the generated `McpController` builds the served MCP server from a
  # registry's tools (`MCP::Server.new(tools: RailsMcp.registry.tools, ...)`).
  #
  # Registration is the app's explicit act of exposing a tool — a fresh registry is
  # empty, so nothing is callable until the app registers it (typically in the
  # generated initializer).
  class Registry
    def initialize
      # Insertion-ordered, keyed by `tool_name` (ADR-0009). Keying by tool name —
      # not class identity — makes registration reload-safe: a Zeitwerk reload
      # hands us a new class object with the same class name and `tool_name`, and
      # it must replace the stale entry rather than sit alongside it (which would
      # make `MCP::Server` raise `ToolNotUnique` on the next request).
      @tools = {}
    end

    # Add a tool class to the allow-list, keyed by its `tool_name` (ADR-0009).
    #
    # - Same class object, or a reload of it (same class name, new object) under an
    #   already-claimed `tool_name`: **replaces** the stale entry — idempotent and
    #   reload-safe, so `tools` never holds two classes sharing a `tool_name`.
    # - A *different* class (different class name) claiming a taken `tool_name`:
    #   raises `ToolNameCollision`, naming both — a genuine integrity error.
    #
    # Returns the tool so `register MyTool` reads as a declaration.
    def register(tool_class)
      key = key_for(tool_class)
      existing = @tools[key]
      if existing && !same_tool?(existing, tool_class)
        raise ToolNameCollision.new(key, existing, tool_class)
      end
      @tools[key] = tool_class
      tool_class
    end

    # Whether a tool with this class's `tool_name` is on the allow-list. Answered by
    # `tool_name`, so a reloaded class reports registered (ADR-0009).
    def registered?(tool_class)
      @tools.key?(key_for(tool_class))
    end

    # The registered tool classes, in registration order. This is the exact set the
    # mounted server advertises and will call.
    def tools
      @tools.values
    end

    # Empty the allow-list. Primarily for tests and re-initialization.
    def clear
      @tools.clear
      self
    end

    private

    # The allow-list key: the tool's `tool_name`. Falls back to class identity only
    # for a class that declares no `tool_name` (each anonymous/unnamed class then
    # keys distinctly, so nothing is silently merged).
    def key_for(tool_class)
      tool_class.tool_name || tool_class
    end

    # Two registrations are "the same tool" when they are the same object, or a
    # reload of it: same non-nil class name (a Zeitwerk reload hands back a new
    # object with the same `Foo::BarTool` name). Anonymous classes (nil name) are
    # the same only by object identity, so two distinct anonymous classes on one
    # `tool_name` still surface as a collision.
    def same_tool?(existing, incoming)
      return true if existing.equal?(incoming)

      existing_name = existing.name
      incoming_name = incoming.name
      !existing_name.nil? && existing_name == incoming_name
    end
  end

  class << self
    # The process-wide default registry. The generated initializer registers the
    # app's tools here, and the generated `McpController` reads it
    # (`RailsMcp.registry.tools`) unless given an explicit registry.
    def registry
      @registry ||= Registry.new
    end
  end
end
