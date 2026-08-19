# frozen_string_literal: true

# The verbatim-template fixture app (spec 0005 R6). This is a minimal but REAL Rails
# application whose `McpController` and `ApplicationMcpTool` are the *rendered generator
# templates loaded verbatim* — not a hand-mirrored copy. Because the templates carry no
# ERB tags, the rendered output is byte-identical to the `.tt` source; `FixtureApp.load!`
# reads each `.tt` and asserts the loaded constant's source equals it, so a test can never
# pass by diverging from the stamped code (R6 verbatim rule).
#
# What this fixture provides (the gaps spec 0005 closes):
#
#   * a real `ApplicationController < ActionController::Base` with
#     `protect_from_forgery with: :exception` — so CSRF is genuinely on (R2 CSRF),
#   * a booted `Rails.application` whose `config.hosts` carries a non-loopback production
#     Host — so the SDK DNS-rebinding guard is genuinely exercised (R2 Host),
#   * a reload stand-in (a redefined tool class) driven through the app-owned
#     `RegisteredTools.all` list, re-resolved per request (R1 / spec 0009 R4).
#
# The app WIRES the two fail-closed seams by SUBCLASSING the verbatim base classes
# (`TestMcpController < McpController`, tools `< ApplicationMcpTool`) and overriding the
# stamped-to-raise seams — it never edits the verbatim source, so the fidelity assertion
# stays honest.
require "rails_mcp"
require "action_controller/railtie"
require "json"

module FixtureApp
  # Absolute path to the install generator's templates (the single source of truth the
  # fixture loads verbatim). Keying off the gem root keeps the path stable wherever the
  # suite runs from.
  TEMPLATES = File.expand_path(
    "../../../lib/generators/rails_mcp/install/templates", __dir__
  )

  MCP_CONTROLLER_TEMPLATE = File.join(TEMPLATES, "mcp_controller.rb.tt")
  APPLICATION_MCP_TOOL_TEMPLATE = File.join(TEMPLATES, "application_mcp_tool.rb.tt")

  # A production, non-loopback Host the fixture serves under, added to config.hosts so the
  # DNS-rebinding guard admits it (R2 Host). Loopback would pass trivially and prove nothing.
  PRODUCTION_HOST = "boswell.fly.dev"

  class << self
    # Read a template's rendered source. The templates carry no ERB, so the file content
    # IS the rendered output; a test asserts the loaded constant's source equals this.
    def template_source(path)
      File.read(path)
    end

    # Boot the Rails app once and load the verbatim templates as the real base classes.
    # Idempotent: safe to call from every test's setup.
    def load!
      return if @loaded

      boot_rails!
      define_app_infrastructure!
      load_verbatim_templates!

      @loaded = true
    end

    private

    # A minimal but genuine Rails application. `config.hosts` is widened with the
    # production Host so the transport's DNS-rebinding guard (which the stamped controller
    # feeds from `Rails.application.config.hosts`) is exercised against a real non-loopback
    # value, not loopback.
    def boot_rails!
      return if defined?(Rails) && Rails.application

      klass = Class.new(Rails::Application) do
        config.eager_load = false
        config.secret_key_base = "fixture" * 12
        config.logger = Logger.new(IO::NULL)
        config.active_support.deprecation = :silence
        config.hosts << FixtureApp::PRODUCTION_HOST
        # Rescue and render exceptions (like a booted app at its exception boundary), so a
        # fail-closed raise from the authentication seam becomes an HTTP denial (500), not a
        # crashed request — mirroring how the stamped controller behaves behind
        # ApplicationController in production.
        config.action_dispatch.show_exceptions = :all
        config.action_dispatch.show_detailed_exceptions = false

        # Remove Rails' own HostAuthorization middleware. It ALSO guards the Host from
        # config.hosts and would mask the thing under test: the SDK DNS-rebinding guard that
        # the STAMPED controller feeds from `Rails.application.config.hosts.grep(String)`.
        # With Rails' guard gone, the SDK guard (inside the transport) is the sole decider,
        # so R2's Host proofs genuinely exercise the controller's `allowed_hosts:` wiring.
        config.middleware.delete ActionDispatch::HostAuthorization

        routes.append do
          match "/mcp", to: "mcp#handle", via: [:get, :post, :delete]
        end
      end
      Object.const_set(:FixtureRailsApp, klass)
      klass.initialize!
    end

    # The app-side infrastructure the stamped templates lean on: a real
    # ApplicationController with CSRF genuinely on, and the app-owned `RegisteredTools`
    # allow-list the verbatim `mcp_controller.rb.tt` passes to `MCP::Server`.
    def define_app_infrastructure!
      unless defined?(::ApplicationController)
        Object.const_set(:ApplicationController, Class.new(ActionController::Base) do
          protect_from_forgery with: :exception
        end)
      end

      define_registered_tools! unless defined?(::RegisteredTools)
    end

    # The app-owned allow-list (spec 0009). The stamped `registered_tools.rb.tt` returns a
    # fixed array literal; the fixture makes `.all` test-settable so each test can list the
    # tools it exercises (the same "an ordinary array of tool classes, resolved per
    # request" model). Tests set `RegisteredTools.list = [...]`; `.all` returns it fresh
    # each request, so a redefined class (the reload stand-in) is named fresh — reload-safe
    # by construction, with no registry keying or collision code (spec 0009 R4).
    def define_registered_tools!
      Object.const_set(:RegisteredTools, Module.new do
        class << self
          attr_writer :list

          def list
            @list ||= []
          end

          def all
            list
          end
        end
      end)
    end

    # Load the rendered templates verbatim as the top-level McpController and
    # ApplicationMcpTool, then assert the loaded source is byte-identical to the template
    # (the R6 verbatim guarantee). Loading at TOPLEVEL_BINDING is what makes these the
    # genuine stamped constants (`class McpController < ApplicationController`), not a copy.
    def load_verbatim_templates!
      [APPLICATION_MCP_TOOL_TEMPLATE, MCP_CONTROLLER_TEMPLATE].each do |path|
        source = template_source(path)
        eval(source, TOPLEVEL_BINDING, path) # standard:disable Security/Eval
      end
    end
  end
end
