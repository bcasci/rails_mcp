# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "json"
require_relative "dummy_app/harness"

# T7 / R3, R4, R9, R10, R11 integrated — the end-to-end proof that the gem's frozen
# seams work through a real mounted /mcp: a stateless MCP JSON-RPC round-trip over the
# official gem's transport, driven with rack-test against a minimal APP-SIDE dummy app
# (its own ApplicationMcpTool, staff user, tenant, and token->user wiring). Real objects
# throughout; the only stubs are the app-side identities the gem never defines.
class EndToEndTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @app = DummyApp::Harness.app
    @events = []
    # The AUDIT SEAM (R4): the app subscribes to the one gem event and would persist a
    # row. Here we collect payloads to assert exactly-once + attribution.
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*, payload|
      @events << payload
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    DummyApp::Current.reset
  end

  attr_reader :app

  def json_rpc(method, params = {}, token: nil, id: 1)
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    header "Authorization", "Bearer #{token}" if token
    post "/", JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
    JSON.parse(last_response.body)
  end

  # R10: through the mounted endpoint, only the registered read-only tool is listed.
  def test_only_registered_tools_are_listed
    body = json_rpc("tools/list", token: "acme-admin-token")
    names = body.dig("result", "tools").map { |t| t["name"] }

    assert_equal ["household_lookup"], names
  end

  # R5/R10: the one advertised tool carries readOnlyHint — v1 exposes read-only only.
  def test_the_advertised_tool_is_read_only
    body = json_rpc("tools/list", token: "acme-admin-token")
    tool = body.dig("result", "tools").first

    assert_equal true, tool.dig("annotations", "readOnlyHint")
  end

  # R10: a tools/call naming a tool that is not registered is refused (allow-list).
  def test_unregistered_tool_call_is_refused
    body = json_rpc("tools/call", {name: "rails_console", arguments: {}}, token: "acme-admin-token")

    assert body["error"], "an unregistered tool must be refused"
    refute body["result"]
  end

  # R3/R9: a call with no resolved staff identity (no/unknown bearer token) fails
  # closed — the app's authorize denies and perform never runs.
  def test_call_without_resolved_identity_fails_closed
    body = json_rpc("tools/call", {name: "household_lookup", arguments: {household_id: 42}})

    assert body["error"], "unresolved identity must fail closed"
    assert_no_perform_result(body)
  end

  # R3: an authorized call runs perform and returns its result to the client.
  def test_authorized_call_runs_and_returns_the_result
    body = json_rpc(
      "tools/call",
      {name: "household_lookup", arguments: {household_id: 42}},
      token: "acme-admin-token"
    )

    assert_equal "household 42 on tenant acme", body.dig("result", "content", 0, "text")
  end

  # R4/R9: an authorized call emits exactly one audit event attributed to the real
  # staff user (the human, not a generic AI identity).
  def test_authorized_call_emits_one_audit_event_attributed_to_the_staff_user
    json_rpc(
      "tools/call",
      {name: "household_lookup", arguments: {household_id: 42}},
      token: "acme-admin-token"
    )

    assert_equal 1, @events.size, "exactly one audit event per invocation"
    assert_same DummyApp::Harness::ACME_ADMIN, @events.first[:user],
      "the event attributes the call to the acting staff user"
    assert_equal "household_lookup", @events.first[:tool]
  end

  # R4: a denied call still emits exactly one audit event, recording the error — the
  # audit log captures the denied attempt too.
  def test_denied_call_emits_one_audit_event_recording_the_error
    json_rpc("tools/call", {name: "household_lookup", arguments: {household_id: 42}})

    assert_equal 1, @events.size, "a denied call still emits exactly one event"
    assert_instance_of RailsMcp::NotAuthorized, @events.first[:error]
    refute @events.first.key?(:result), "a denied call carries error:, not result:"
  end

  # R4: the raw bearer token never reaches the audit payload (no credential in the
  # event — ADR-0004 / R4).
  def test_audit_payload_carries_no_bearer_token
    json_rpc(
      "tools/call",
      {name: "household_lookup", arguments: {household_id: 42}},
      token: "acme-admin-token"
    )

    serialized = @events.first.inspect
    refute_includes serialized, "acme-admin-token", "the bearer token must not appear in the audit payload"
  end

  # R11: a cross-tenant reach is denied by the DUMMY APP's own wiring (same human,
  # tenant they may not act on) — proving the gem's authorize seam is usable for
  # tenancy, not that the gem enforces it.
  def test_cross_tenant_call_is_denied_by_app_wiring
    body = json_rpc(
      "tools/call",
      {name: "household_lookup", arguments: {household_id: 42}},
      token: "acme-admin-on-globex-token"
    )

    assert body["error"], "a cross-tenant reach must be denied"
    assert_no_perform_result(body)
    assert_instance_of RailsMcp::NotAuthorized, @events.first[:error]
  end

  private

  # The MCP transport surfaces a tool denial as an error, and even where a tool error
  # is delivered inside `result` (isError), it must not carry the perform output.
  def assert_no_perform_result(body)
    text = body.dig("result", "content", 0, "text")
    refute_equal "household 42 on tenant acme", text, "perform must not have run"
  end
end
