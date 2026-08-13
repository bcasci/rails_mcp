# frozen_string_literal: true

require "active_support/notifications"

module RailsMcp
  # The per-call audit seam (SPEC R4, ADR-0004). The gem publishes exactly one
  # `ActiveSupport::Notifications` event per tool invocation and persists nothing
  # itself — the app subscribes to {EVENT} and writes its own audit row.
  #
  # The payload is a frozen public contract: `user:`, `tool:`, `args:`, and
  # exactly one of `result:` (success) or `error:` (failure). No other keys — in
  # particular no bearer token or credential ever enters the payload.
  module Instrumentation
    # The single canonical event name. Reference this constant; never hardcode
    # the string (docs/conventions.md, SPEC R4).
    EVENT = "invoke.rails_mcp"

    module_function

    # Run +block+ as one instrumented tool invocation, publishing exactly one
    # {EVENT} notification whether the block returns or raises.
    #
    # On success the payload carries `result:` (the block's return value); on a
    # raise it carries `error:` (the exception) and the exception is re-raised to
    # the caller. Returns the block's value on success.
    #
    # @param user [Object] the acting user resolved app-side (never nil-checked here)
    # @param tool [String, Class] the tool name/class being invoked
    # @param args [Hash] the declared args for this call
    def instrument(user:, tool:, args:)
      payload = {user: user, tool: tool, args: args}
      raised = nil
      result = nil

      # Run the block and capture its outcome first, then publish. This keeps the
      # payload keys exactly the frozen contract — letting the raise escape
      # ActiveSupport::Notifications.instrument would inject its own :exception /
      # :exception_object keys, which the R4 contract forbids.
      begin
        result = yield
        payload[:result] = result
      rescue => error
        payload[:error] = error
        raised = error
      end

      ActiveSupport::Notifications.instrument(EVENT, payload)

      raise raised if raised
      result
    end
  end
end
