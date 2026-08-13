# frozen_string_literal: true

require "rails/generators"

module RailsMcp
  module Generators
    # `rails g rails_mcp:install` (SPEC R8, Devise-style). Scaffolds everything an app
    # needs to start: the app-owned, fail-closed `ApplicationMcpTool` (R7), one
    # read-only example tool, an initializer, the `/mcp` mount via `mount_mcp` (R6),
    # and example tests (authz denial + audit-row-written).
    #
    # Everything this stamps is app-owned and editable — the gem ships no policy
    # (ADR-0004). The templates reference the gem's public API (`RailsMcp::Tool`,
    # `mount_mcp`, `RailsMcp.registry`, the `invoke.rails_mcp` event) but the seams'
    # bodies are the app's to fill in.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install rails_mcp: app-owned ApplicationMcpTool, an initializer, the " \
           "/mcp route, a read-only example tool, and example tests."

      # The app-owned base tool, mirroring ApplicationController. Fail-closed: its
      # stamped `authorize` denies (R7). Scoping is a commented, optional note — the
      # gem presumes no tenancy (R11).
      def create_application_mcp_tool
        template "application_mcp_tool.rb.tt", "app/mcp/application_mcp_tool.rb"
      end

      # One read-only example tool subclassing the app-owned base (R8).
      def create_example_tool
        template "example_read_only_tool.rb.tt", "app/mcp/example_read_only_tool.rb"
      end

      # The initializer at the DECIDED path (R8): registers the example tool on the
      # process-wide registry (the allow-list) and points at the audit subscribe seam.
      def create_initializer
        template "initializer.rb.tt", "config/initializers/rails_mcp.rb"
      end

      # Example tests expressing the two safety checks: authz denial and
      # audit-row-written (R8).
      def create_example_tests
        template "example_tests.rb.tt", "test/mcp/example_read_only_tool_test.rb"
      end

      # The one-line `/mcp` mount in config/routes.rb (R6, R8). Injected inside the
      # `routes.draw` block; a template documents the same line for apps that route
      # differently.
      def add_mount_route
        route_content = File.read(File.expand_path("templates/routes_mount.rb.tt", __dir__)).strip
        route route_content
      end
    end
  end
end
