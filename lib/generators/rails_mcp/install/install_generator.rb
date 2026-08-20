# frozen_string_literal: true

require "rails/generators"

module RailsMcp
  module Generators
    # `rails g rails_mcp:install` (SPEC R8, Devise-style). Scaffolds everything an app
    # needs to start: the app-owned, fail-closed `ApplicationMcpTool` (R7), one
    # read-only example tool, the app-owned `RegisteredTools` allow-list, an
    # initializer, a fail-closed `McpController` in front of the `/mcp` endpoint
    # (spec 0002 R2), the route to that controller (R3), and example tests (authz
    # denial + audit-row-written).
    #
    # Everything this stamps is app-owned and editable — the gem ships no policy or
    # authentication (ADR-0004). The templates reference the gem's public API
    # (`RailsMcp::Tool`) and the official `mcp` gem's public controller pattern
    # (`MCP::Server` + `StreamableHTTPTransport#handle_request`), but the seams'
    # bodies and the tool list are the app's to fill in.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install rails_mcp: app-owned ApplicationMcpTool, an initializer, a " \
           "fail-closed McpController and the /mcp route to it, a read-only example " \
           "tool, and example tests."

      # The app-owned base tool, mirroring ApplicationController. Fail-closed: its
      # stamped `authorize` denies (R7).
      def create_application_mcp_tool
        template "application_mcp_tool.rb.tt", "app/mcp/application_mcp_tool.rb"
      end

      # One read-only example tool subclassing the app-owned base (R8).
      def create_example_tool
        template "example_read_only_tool.rb.tt", "app/mcp/example_read_only_tool.rb"
      end

      # The app-owned allow-list (R2): a RegisteredTools module whose `.all` returns
      # the explicit array of tool classes the AI may call, seeded with the example
      # tool. McpController passes RegisteredTools.all to MCP::Server per request.
      def create_registered_tools
        template "registered_tools.rb.tt", "app/mcp/registered_tools.rb"
      end

      # The initializer at the DECIDED path (R8): subscribes to the audit event. It no
      # longer registers tools — the allow-list lives in app/mcp/registered_tools.rb.
      def create_initializer
        template "initializer.rb.tt", "config/initializers/rails_mcp.rb"
      end

      # Example tests expressing the two safety checks: authz denial and
      # audit-row-written (R8).
      def create_example_tests
        template "example_tests.rb.tt", "test/mcp/example_read_only_tool_test.rb"
      end

      # The RegisteredTools guard test (spec 0014 R3): fails if any listed tool is not a
      # RailsMcp::Tool subclass or overrides `call` (bypassing authorize/audit/allow-list)
      # unless the app signs off via ALLOWLISTED_RAW_TOOLS — making a raw tool a visible,
      # deliberate exception rather than a silent one. Opt-in and app-side; the gem still
      # neither warns nor blocks at runtime (ADR-0004, ADR-0007).
      def create_registered_tools_guard_test
        template "registered_tools_guard_test.rb.tt", "test/mcp/registered_tools_guard_test.rb"
      end

      # The app-owned, fail-closed McpController in front of the /mcp endpoint
      # (spec 0002 R2). Inherits ApplicationController so it reuses the app's own
      # auth stack; its authentication seam raises by default until wired.
      def create_mcp_controller
        template "mcp_controller.rb.tt", "app/controllers/mcp_controller.rb"
      end

      # The `/mcp` route in config/routes.rb (spec 0002 R3). Routes the MCP request
      # verbs (POST, GET, DELETE) to McpController#handle — not a bare transport mount —
      # so the app authenticates and resolves the acting user before any tool runs.
      # Injected inside the `routes.draw` block.
      def add_mount_route
        route_content = File.read(File.expand_path("templates/routes_mount.rb.tt", __dir__)).strip
        route route_content
      end

      # Post-run notice (spec 0002 R4): the /mcp endpoint denies until the implementor
      # wires authentication in McpController, naming the file.
      def print_security_notice
        say ""
        say "SECURITY: the /mcp endpoint is UNAUTHENTICATED until you secure it.", :yellow
        say "It is fail-closed by default — every request is denied and no tool runs " \
            "until you wire your real authentication check in " \
            "app/controllers/mcp_controller.rb (McpController#authenticate_acting_user!).",
          :yellow
      end
    end
  end
end
