# frozen_string_literal: true

module DummyApp
  # An APP-SIDE stub of a real staff User — the human the AI acts as. The gem never
  # defines or resolves this; the dummy app owns it (ADR-0004, R9). It carries the
  # tenant ids this staff member is allowed to act on so the app's own `authorize`
  # can deny a cross-tenant reach (R11 — enforced by app wiring, not the gem).
  class StaffUser
    attr_reader :id, :name, :allowed_tenant_ids

    def initialize(id:, name:, allowed_tenant_ids:)
      @id = id
      @name = name
      @allowed_tenant_ids = allowed_tenant_ids
    end

    # Whether this staff user may act on the given tenant. App policy, not gem code.
    def may_act_on?(tenant)
      tenant && allowed_tenant_ids.include?(tenant.id)
    end
  end
end
