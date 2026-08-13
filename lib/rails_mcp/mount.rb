# frozen_string_literal: true

require "mcp"

module RailsMcp
  # The transport mount (SPEC R6). `mount_mcp '/mcp'` in `config/routes.rb` mounts the
  # official `mcp` gem's Rack transport, in stateless mode (ADR-0002), serving the
  # tools on a registry (the allow-list, R10) at the given path — in the same Rails
  # process as the web app.
  #
  # The protocol itself (JSON-RPC, the HTTP transport, schemas) is entirely the `mcp`
  # gem's; this module only wires a `RailsMcp::Registry` to an `MCP::Server` +
  # stateless `StreamableHTTPTransport` and exposes the routing helper (ADR-0001).
  module Mount
    # Default MCP server name advertised to clients. Apps override via `server_name:`.
    DEFAULT_SERVER_NAME = "rails_mcp"

    module_function

    # Build the Rack app that serves the registry's tools over MCP. Returns the
    # stateless `MCP::Server::Transports::StreamableHTTPTransport`, which is itself a
    # Rack app (`#call(env)`), ready to be mounted.
    #
    # @param registry [RailsMcp::Registry] the allow-list of tools to serve.
    # @param server_name [String] the MCP server name advertised to clients.
    # @param allowed_hosts [Array<String>, nil] extra Host values the SDK's
    #   DNS-rebinding guard accepts (the app's own hosts in a real deploy).
    # @param allowed_origins [Array<String>, nil] extra Origin values accepted.
    # @param dns_rebinding_protection [Boolean] pass false only when an upstream
    #   proxy already validates Host/Origin.
    def rack_app(
      registry: RailsMcp.registry,
      server_name: DEFAULT_SERVER_NAME,
      allowed_hosts: nil,
      allowed_origins: nil,
      dns_rebinding_protection: true
    )
      server = MCP::Server.new(name: server_name, tools: registry.tools)
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server,
        stateless: true,
        allowed_hosts: allowed_hosts,
        allowed_origins: allowed_origins,
        dns_rebinding_protection: dns_rebinding_protection
      )
      server.transport = transport
      transport
    end

    # The routing helper mixed into the Rails router. `mount_mcp '/mcp'` mounts the
    # stateless MCP Rack app at `path`. Extra keyword args are passed through to
    # {rack_app} (e.g. `registry:`, `allowed_hosts:`).
    module Router
      def mount_mcp(path, **options)
        mount RailsMcp::Mount.rack_app(**options) => path
      end
    end
  end

  class << self
    # Public entry point: the stateless MCP Rack app for the registry's tools.
    # Delegates to {Mount.rack_app}. `mount_mcp` uses this under the hood; expose it
    # directly so an app can mount at a custom path or inspect the app.
    def rack_app(**options)
      Mount.rack_app(**options)
    end
  end
end

# Make `mount_mcp` available in `config/routes.rb` when Rails' routing DSL is loaded.
# Guarded so the gem still loads (and its unit tests run) without Rails present; the
# Router mixin is tested directly.
if defined?(ActionDispatch::Routing::Mapper)
  ActionDispatch::Routing::Mapper.include(RailsMcp::Mount::Router)
end
