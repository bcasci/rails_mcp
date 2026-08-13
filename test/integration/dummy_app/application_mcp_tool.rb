# frozen_string_literal: true

module DummyApp
  # The APP-OWNED base tool, as a real app would stamp it (mirrors the generator's
  # template, R7). It wires the two frozen gem seams to the dummy app's own stack:
  #
  #   authorize(user:, args:, tool:) — fail-closed real check (R3): denies when no
  #     staff identity was resolved, and denies a cross-tenant reach (R11). The gem
  #     ships none of this; it lives here, app-side.
  #
  # The audit seam is the "invoke.rails_mcp" notification the gem publishes; the app
  # subscribes and persists (done in the integration test's setup).
  class ApplicationMcpTool < RailsMcp::Tool
    def authorize(user:, args:, tool:, **)
      # Fail closed: no resolved staff identity ⇒ deny (R3, R9).
      raise RailsMcp::NotAuthorized, "no staff user" if user.nil?

      # Cross-tenant denial is APP wiring (R11): the tenant comes from the
      # authenticated context, never a free tool arg, and the app denies a staff
      # user reaching a tenant they may not act on.
      tenant = current_tenant
      unless user.may_act_on?(tenant)
        raise RailsMcp::NotAuthorized, "staff user #{user.id} may not act on this tenant"
      end
    end

    private

    # The target tenant, resolved app-side from the authenticated request (the Rack
    # layer stashed it in Current) — never a tool arg. Nil in a single-tenant install.
    def current_tenant
      DummyApp::Current.tenant
    end
  end
end
