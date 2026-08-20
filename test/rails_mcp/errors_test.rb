# frozen_string_literal: true

require "test_helper"

# RailsMcp exception hierarchy (SPEC R5, ARCH-04). The error classes live together
# in lib/rails_mcp/errors.rb, required first from the entry file. These assert the
# hierarchy resolves from a clean load and that the fail-closed default authorize
# still raises RailsMcp::NotAuthorized.
class RailsMcp::ErrorsTest < Minitest::Test
  # R5: requiring the gem loads cleanly and RailsMcp::Error resolves.
  def test_error_base_class_resolves
    assert_operator RailsMcp::Error, :<, StandardError
  end

  # R5: RailsMcp::NotAuthorized resolves and is a RailsMcp::Error subclass.
  def test_not_authorized_is_an_error_subclass
    assert_operator RailsMcp::NotAuthorized, :<, RailsMcp::Error
  end

  # R5: NotAuthorized carries the developer detail attribute moved from tool.rb.
  def test_not_authorized_carries_detail
    error = RailsMcp::NotAuthorized.new("not authorized", detail: "why")

    assert_equal "not authorized", error.message
    assert_equal "why", error.detail
  end

  # R5: an unimplemented (default) authorize still fails closed, raising
  # RailsMcp::NotAuthorized resolved from errors.rb.
  def test_default_authorize_raises_not_authorized
    klass = Class.new(RailsMcp::Tool) { tool_name "denied" }

    assert_raises(RailsMcp::NotAuthorized) do
      klass.call(server_context: {user: :staff})
    end
  end
end
