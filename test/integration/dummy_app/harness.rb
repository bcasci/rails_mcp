# frozen_string_literal: true

require "rails_mcp"
require_relative "current"
require_relative "tenant"
require_relative "staff_user"
require_relative "application_mcp_tool"
require_relative "household_lookup_tool"

module DummyApp
  # The APP-SIDE wiring a real Rails app owns: token -> staff user + tenant resolution,
  # the tool allow-list (registry), and the Rack layer that populates the gem's
  # server_context with the resolved staff user (R9) before delegating to the official
  # gem's mounted transport (R6). None of this is gem code — it proves the gem's seams
  # are usable end to end.
  module Harness
    module_function

    # Two tenants; ACME's admin may act only on ACME, so a Globex request from that
    # token is a cross-tenant reach the app denies (R11).
    ACME = Tenant.new(id: "acme")
    GLOBEX = Tenant.new(id: "globex")

    ACME_ADMIN = StaffUser.new(id: 1, name: "Ada (ACME admin)", allowed_tenant_ids: ["acme"])

    # APP-SIDE bearer-token -> (staff user, tenant) table. A real app validates the
    # token against its own store; here it's a fixed map. The raw token never leaves
    # this layer — it is not put on server_context or in the audit payload (R4).
    TOKENS = {
      "acme-admin-token" => {user: ACME_ADMIN, tenant: ACME},
      # Same human, but the request targets a tenant they may not act on.
      "acme-admin-on-globex-token" => {user: ACME_ADMIN, tenant: GLOBEX}
    }.freeze

    # The allow-list: only HouseholdLookupTool is registered, so only it is callable
    # (R10). No console/arbitrary-Ruby tool exists anywhere in the surface.
    def registry
      @registry ||= RailsMcp::Registry.new.tap { |r| r.register(HouseholdLookupTool) }
    end

    # Build the Rack app the dummy app mounts at /mcp. Per request it resolves the
    # bearer token to a staff user + tenant (app-side, R9), stashes the tenant in
    # Current for app authorize (R11), sets the gem server_context so the acting user
    # reaches authorize + the audit payload, then delegates to the official gem's
    # stateless transport.
    def app
      transport = RailsMcp.rack_app(registry: registry, allowed_hosts: ["example.org"])
      server = transport.instance_variable_get(:@server)

      lambda do |env|
        request = Rack::Request.new(env)
        token = bearer_token(request)
        resolved = TOKENS[token]

        DummyApp::Current.tenant = resolved && resolved[:tenant]
        # The gem only ever sees the resolved user — never the raw token (R9, R4).
        server.server_context = {user: resolved && resolved[:user]}

        transport.call(env)
      ensure
        DummyApp::Current.reset
        server.server_context = nil
      end
    end

    def bearer_token(request)
      header = request.get_header("HTTP_AUTHORIZATION")
      return nil unless header

      header.sub(/\ABearer /, "")
    end
  end
end
