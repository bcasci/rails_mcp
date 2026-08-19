# frozen_string_literal: true

require "mcp"
require_relative "args"
require_relative "annotations"
require_relative "instrumentation"

module RailsMcp
  # Raised when a tool's `authorize` seam denies the call. The default `authorize`
  # raises this (fail-closed, R3); app overrides raise it (or their own error) on a
  # failed policy check. The invoke pipeline lets it propagate after emitting the one
  # audit event, so the SDK surfaces an authorization error and `perform` never ran.
  class NotAuthorized < Error; end

  # The base class every app tool subclasses, directly or via the generated
  # `ApplicationMcpTool` (SPEC R1–R5). It is an `MCP::Tool`, so the official gem owns
  # the protocol, schema validation, and annotation serialization (ADR-0001); this
  # class adds the conventions and the two frozen seams:
  #
  #   authorize(user:, args:, tool:)   # R3 — runs before perform, fails closed
  #   perform(**declared_args)         # R2 — the tool's behavior, returns a result
  #
  # and wraps every invocation as **authorize -> perform -> notify**, emitting exactly
  # one `invoke.rails_mcp` audit event per call whether it succeeds, is denied, or
  # raises (R4). The gem ships no policy: `authorize` denies by default and identity is
  # resolved app-side and handed in via the SDK's server_context (R9, ADR-0004).
  class Tool < MCP::Tool
    extend Args
    extend Annotations

    class << self
      # The SDK entry point. `MCP::Server` invokes a tool by calling this class method
      # as `call(**arguments, server_context:)` (see mcp gem's call_tool_with_args).
      #
      # We extract the acting user from the app-populated server_context, drop any
      # undeclared arguments (R1 allow-list on args), then run the invoke pipeline on a
      # fresh instance. The single audit event wraps authorize + perform so a denial or
      # a raise still emits exactly one event (R4).
      def call(server_context: nil, **arguments)
        user = user_from(server_context)
        args = declared_arguments(arguments)

        new.send(:invoke, user: user, args: args)
      end

      # Build a text tool result. Convenience so a class-level `call` override or a test
      # can produce the same result shape as the instance helper.
      def text_response(text)
        MCP::Tool::Response.new([{type: "text", text: text}])
      end

      private

      # Pull the acting user out of the app-populated context without inventing
      # one. The app sets `server_context` on `MCP::Server`; the gem never resolves or
      # fabricates identity (R9). Supports a Hash context (`{user: ...}`) and any object
      # exposing `user` — including the SDK's `MCP::ServerContext`, which delegates
      # `[]`/`user` to the underlying app context. Absent user is `nil` (fail-closed is
      # the app's `authorize` job, not a gem-invented identity).
      def user_from(server_context)
        return nil if server_context.nil?

        if server_context.respond_to?(:user)
          server_context.user
        elsif server_context.respond_to?(:[])
          server_context[:user]
        end
      end
    end

    # Run one invocation: authorize, then perform, all inside the single audit event.
    # `authorize` runs first, so a denial keeps `perform` from running; the event still
    # fires exactly once (recording the error) because it wraps the whole pipeline (R3,
    # R4). Re-raises whatever authorize/perform raised so the SDK surfaces the error.
    #
    # @api private
    def invoke(user:, args:)
      Instrumentation.instrument(user: user, tool: audit_tool_name, args: args) do
        authorize(user: user, args: args, tool: self)
        perform(**args)
      end
    end

    # The authorization seam (R3). Fail-closed default: the gem ships no policy, so an
    # unoverridden `authorize` denies. Apps override this in `ApplicationMcpTool` to run
    # their own check (e.g. Pundit) and raise/deny on failure. Accepts `**` so app
    # overrides stay forward-compatible with future context keys.
    def authorize(user:, args:, tool:)
      raise NotAuthorized,
        "authorize is not implemented; #{self.class.name || "this tool"} denies by default. " \
        "Override authorize in ApplicationMcpTool to permit calls."
    end

    # The tool's behavior (R2). Subclasses override with the declared args as keywords
    # and return a response the transport can serialize (e.g. via `text_response`).
    def perform(**declared_args)
      raise NotImplementedError, "#{self.class.name || "tool"} must implement #perform"
    end

    # Build a text tool result (R2). `text_response("ok")` yields a single text content
    # item equal to "ok".
    def text_response(text)
      self.class.text_response(text)
    end

    private

    # The tool identifier the audit event carries (R4 `tool:`). Prefer the advertised
    # MCP tool name; fall back to the Ruby class name so anonymous/test classes still
    # attribute the call.
    def audit_tool_name
      self.class.tool_name || self.class.name
    end
  end
end
