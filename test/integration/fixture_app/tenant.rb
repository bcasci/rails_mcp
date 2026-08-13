# frozen_string_literal: true

module FixtureApp
  # A sharded-tenant stand-in with an OBSERVABLE `with_shard` (spec 0005 R3). The gem has
  # no tenant concept (ADR-0004); this exists only in the fixture. `with_shard` sets a
  # thread-local shard id for the duration of the block and restores it after, exactly the
  # shape `Current.tenant.with_shard { ... }` assumes in the stamped controller's guidance.
  # A tool (or `authorize`) reads `FixtureApp::Tenant.active_shard` to observe whether it
  # ran in-shard — the fixture's proof that the wrap covers BOTH authorize and perform.
  class Tenant
    attr_reader :id

    def initialize(id)
      @id = id
    end

    def with_shard
      previous = Thread.current[:fixture_active_shard]
      Thread.current[:fixture_active_shard] = id
      yield
    ensure
      Thread.current[:fixture_active_shard] = previous
    end

    # The shard active on the current thread, or nil when unscoped. Read by tools and by
    # the app's authorize to prove in-shard execution.
    def self.active_shard
      Thread.current[:fixture_active_shard]
    end
  end
end
