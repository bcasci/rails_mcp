# frozen_string_literal: true

module FixtureApp
  # App-side per-request context, the way a real app uses ActiveSupport::CurrentAttributes.
  # The stamped controller's tenant guidance reads `Current.tenant.with_shard`; this stand-in
  # supplies exactly that shape. The gem knows nothing about it (ADR-0004).
  module Current
    class << self
      def tenant
        Thread.current[:fixture_current_tenant]
      end

      def tenant=(tenant)
        Thread.current[:fixture_current_tenant] = tenant
      end

      def reset
        Thread.current[:fixture_current_tenant] = nil
      end
    end
  end
end
