# frozen_string_literal: true

module DummyApp
  # APP-SIDE per-request context, the way a real app uses ActiveSupport::CurrentAttributes:
  # the Rack layer that validates the bearer token resolves the staff user and the target
  # tenant and stashes them here for the request. The gem knows nothing about this — it
  # only threads `user:` through server_context (R9). The app reads the tenant here so its
  # own `authorize` can scope by it (R11), never from a tool arg.
  module Current
    class << self
      def tenant
        Thread.current[:dummy_app_tenant]
      end

      def tenant=(tenant)
        Thread.current[:dummy_app_tenant] = tenant
      end

      def reset
        Thread.current[:dummy_app_tenant] = nil
      end
    end
  end
end
