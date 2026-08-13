# frozen_string_literal: true

module DummyApp
  # An APP-SIDE stub tenant. The gem has NO tenant concept (ADR-0004, R11); this
  # exists only in the dummy app to prove the app can wire cross-tenant denial in its
  # own `authorize`. A real app would run tool bodies inside `tenant.with_shard { ... }`.
  class Tenant
    attr_reader :id

    def initialize(id:)
      @id = id
    end
  end
end
