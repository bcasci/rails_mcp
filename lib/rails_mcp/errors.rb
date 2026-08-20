# frozen_string_literal: true

module RailsMcp
  # Base class for every error the gem raises. Kept here — with its subclasses —
  # so the exception hierarchy lives in one file and is required first from the
  # entry file (ARCH-04).
  class Error < StandardError; end

  # Raised when a tool's `authorize` seam denies the call. The default `authorize`
  # raises this (fail-closed, R3); app overrides raise it (or their own error) on a
  # failed policy check. The invoke pipeline lets it propagate after emitting the one
  # audit event, so the SDK surfaces an authorization error and `perform` never ran.
  #
  # mcp surfaces a raised message VERBATIM to the AI client (server.rb:798,
  # `Internal error calling tool <name>: <e.message>`), so the client-facing
  # `#message` stays terse ("not authorized") and leaks nothing (SEC-02). Any
  # developer diagnosis — which class denied, that the seam is unimplemented —
  # rides on `#detail`, which never reaches the client but is retained on the
  # exception object the audit event carries in its `error:` payload.
  class NotAuthorized < Error
    # Developer-facing detail for the audit log (not the client message). `nil`
    # when the raiser supplied only a message.
    attr_reader :detail

    def initialize(message = nil, detail: nil)
      super(message)
      @detail = detail
    end
  end
end
