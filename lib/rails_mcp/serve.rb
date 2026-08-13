# frozen_string_literal: true

require "mcp"
require_relative "mount"

module RailsMcp
  # Per-request serve entry point (SPEC R1, R5). The generated `McpController`
  # resolves the acting staff user per request and calls this to run ONE MCP
  # request with that user placed on the SDK `server_context` — for that request
  # only. It returns a Rack response triple the controller sends.
  #
  # Why per-request and not the boot-time mount (`mount_mcp` / {RailsMcp.rack_app}):
  # the `mcp` gem reads `server_context` off the `MCP::Server` INSTANCE (see the
  # SDK's stateless `ephemeral_session`, which dispatches against the shared
  # `@server`). Placing per-request identity on a single process-wide server means
  # mutating shared state — not thread-safe under Puma (ADR-0006). So each `serve`
  # builds a FRESH `MCP::Server` + stateless transport with the acting user set as
  # that server's `server_context` at construction, isolating identity per request.
  #
  # The gem still ships no policy and no authentication (ADR-0004): `serve` only
  # transports the resolved `user:` on `server_context` (ADR-0005). The raw request
  # / env and any bearer token never reach `server_context` or the audit payload —
  # only the resolved user does.
  module Serve
    module_function

    # Serve one MCP request with a per-request acting user.
    #
    # @param request [ActionDispatch::Request, Hash] the request; an
    #   `ActionDispatch::Request` (or anything exposing `#env`) or a raw Rack env
    #   Hash. Tolerant input, like the tool framework's `user_from`.
    # @param user [Object, nil] the resolved acting staff user for THIS request.
    #   It is the only identity placed on `server_context`; `nil` fails closed at
    #   the app's `authorize` (the gem invents no identity).
    # @param registry [RailsMcp::Registry] the allow-list of tools to serve
    #   (defaults to the process-wide registry). Allow-list parity with the direct
    #   mount: only registered tools are listed or callable.
    # @param transport_options [Hash] passed through to the stateless transport
    #   (e.g. `server_name:`, `allowed_hosts:`, `allowed_origins:`,
    #   `dns_rebinding_protection:`) — same options as {RailsMcp.rack_app}.
    # @return [Array(Integer, Hash, #each)] a Rack response triple
    #   `[status, headers, body]`.
    def serve(request, user:, registry: RailsMcp.registry, **transport_options)
      env = rack_env(request)

      # Fresh per-request server carries THIS request's user as its own
      # server_context — no shared, process-wide server is mutated (ADR-0006).
      transport = Mount.rack_app(registry: registry, **transport_options)
      server_for(transport).server_context = {user: user}

      transport.call(env)
    end

    # Extract the Rack env Hash from either an `ActionDispatch::Request`
    # (or any object exposing `#env`) or a raw env Hash. Tolerant on input so the
    # controller can hand `request` straight through.
    def rack_env(request)
      return request if request.is_a?(Hash)
      return request.env if request.respond_to?(:env)

      raise ArgumentError,
        "RailsMcp.serve expects an ActionDispatch::Request or a Rack env Hash, got #{request.class}"
    end
    private_class_method :rack_env

    # The `MCP::Server` behind a freshly built transport. `Mount.rack_app` returns
    # the transport (the Rack app); the SDK's `Transport` stores its server in
    # `@server`, so this is the isolation-correct handle to set per-request context.
    def server_for(transport)
      transport.instance_variable_get(:@server)
    end
    private_class_method :server_for
  end

  class << self
    # Public entry point (SPEC R1): serve one MCP request with a per-request acting
    # user, isolating `server_context` per request. Delegates to {Serve.serve}.
    #
    #   RailsMcp.serve(request, user: acting_staff_user)
    #
    # Returns a Rack response triple `[status, headers, body]`.
    def serve(request, user:, registry: RailsMcp.registry, **transport_options)
      Serve.serve(request, user: user, registry: registry, **transport_options)
    end
  end
end
