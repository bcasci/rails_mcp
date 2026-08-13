# frozen_string_literal: true

module RailsMcp
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
      # Insertion-ordered, de-duplicated set of tool classes.
      @tools = {}
    end

    # Add a tool class to the allow-list. Idempotent: registering the same tool
    # twice does not duplicate it. Returns the tool so `register MyTool` reads as a
    # declaration.
    def register(tool_class)
      @tools[tool_class] = true
      tool_class
    end

    # Whether a tool class is on the allow-list.
    def registered?(tool_class)
      @tools.key?(tool_class)
    end

    # The registered tool classes, in registration order. This is the exact set the
    # mounted server advertises and will call.
    def tools
      @tools.keys
    end

    # Empty the allow-list. Primarily for tests and re-initialization.
    def clear
      @tools.clear
      self
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
