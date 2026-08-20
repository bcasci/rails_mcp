# frozen_string_literal: true

require "test_helper"

# Tests for the per-call audit seam (SPEC R4). The gem publishes exactly one
# `invoke.rails_mcp` ActiveSupport::Notifications event per tool invocation and
# persists nothing itself.
class InstrumentationTest < Minitest::Test
  def setup
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*args|
      @events << ActiveSupport::Notifications::Event.new(*args)
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  # R4: event name is the single canonical constant "invoke.rails_mcp".
  def test_event_name_is_the_canonical_constant
    assert_equal "invoke.rails_mcp", RailsMcp::Instrumentation::EVENT
  end

  # R4: exactly one event per successful invocation.
  def test_success_emits_exactly_one_event
    RailsMcp::Instrumentation.instrument(user: user, tool: "Households::LookupTool", args: {}) { "ok" }

    assert_equal 1, @events.length
  end

  # R4: exactly one event per failing invocation.
  def test_failure_emits_exactly_one_event
    assert_raises(RuntimeError) do
      RailsMcp::Instrumentation.instrument(user: user, tool: "Households::LookupTool", args: {}) do
        raise "boom"
      end
    end

    assert_equal 1, @events.length
  end

  # R4: success payload carries staff user, tool name, args, and a result marker.
  def test_success_payload_carries_user_tool_args_result
    staff = user(id: 7)
    args = {household_id: 42}
    RailsMcp::Instrumentation.instrument(user: staff, tool: "Households::LookupTool", args: args) { "found" }

    payload = @events.first.payload
    assert_same staff, payload[:user]
    assert_equal "Households::LookupTool", payload[:tool]
    assert_equal args, payload[:args]
    assert payload.key?(:result), "success payload must carry a result marker"
  end

  # R4: success payload carries result, never an error key.
  def test_success_payload_has_no_error_key
    RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { "ok" }

    refute @events.first.payload.key?(:error), "success payload must not carry :error"
  end

  # R4: failure payload records the error and carries no result key.
  def test_failure_payload_records_error_and_no_result
    assert_raises(RuntimeError) do
      RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { raise "boom" }
    end

    payload = @events.first.payload
    assert_instance_of RuntimeError, payload[:error]
    assert_equal "boom", payload[:error].message
    refute payload.key?(:result), "failure payload must not carry :result"
  end

  # R4: exactly one of :result / :error is present (success case).
  def test_exactly_one_of_result_or_error_on_success
    RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { "ok" }

    payload = @events.first.payload
    assert payload.key?(:result) ^ payload.key?(:error)
  end

  # R4: the raised error propagates to the caller (perform's raise is surfaced).
  def test_failure_reraises_the_original_error
    error = assert_raises(ArgumentError) do
      RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { raise ArgumentError, "bad" }
    end

    assert_equal "bad", error.message
  end

  # R4: the block's return value is passed through as the instrument result.
  def test_returns_the_block_value
    value = RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { "the-result" }

    assert_equal "the-result", value
  end

  # R4 / ADR-0004: the payload carries no credential key at the TOP level — no
  # bearer/token/password key is grafted onto the event alongside :user/:tool/:args.
  # The input args here carry NONE of these keys, so this only proves the gem adds no
  # credential key of its own; nested-arg leakage is covered by the next test.
  def test_payload_carries_no_top_level_credential_key
    RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {household_id: 42}) { "ok" }

    payload = @events.first.payload
    forbidden = %i[token bearer bearer_token credentials credential password authorization]
    forbidden.each do |key|
      refute payload.key?(key), "payload must not carry credential key #{key.inspect}"
    end
  end

  # R4 / ADR-0004: the gem is a neutral conduit — it neither scrubs nor invents args. A
  # token the CALLER puts in args rides through verbatim (the gem does not read or drop
  # it); the guarantee the gem OWNS is that it grafts no extra credential key and passes
  # args through unchanged. This replaces the old tautological
  # `test_payload_excludes_credentials`, which put the secret under args[:token] but only
  # checked top-level keys the input never had, so it passed regardless of any scrubbing.
  # (The no-leak-on-the-real-HTTP-path invariant — the app resolving a bearer header into
  # a user without ever placing the raw token in args — is proven end to end in
  # test/integration/mcp_request_flow_test.rb.)
  def test_payload_args_are_carried_verbatim_including_a_nested_token
    args = {household_id: 42, token: "secret"}
    RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: args) { "ok" }

    payload = @events.first.payload
    assert_equal args, payload[:args],
      "the gem passes args through verbatim — it neither scrubs nor adds keys"
    assert_equal %i[user tool args result].sort, payload.keys.sort,
      "the token in args grafts no credential key onto the payload; the key set is unchanged"
  end

  # R4 / ADR-0004: the payload keys are exactly the frozen contract, no extras.
  def test_success_payload_keys_are_exactly_the_contract
    RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { "ok" }

    assert_equal %i[user tool args result].sort, @events.first.payload.keys.sort
  end

  def test_failure_payload_keys_are_exactly_the_contract
    assert_raises(RuntimeError) do
      RailsMcp::Instrumentation.instrument(user: user, tool: "T", args: {}) { raise "boom" }
    end

    assert_equal %i[user tool args error].sort, @events.first.payload.keys.sort
  end

  private

  # A stand-in staff user; the gem never resolves identity, it only carries it.
  def user(id: 1)
    Struct.new(:id).new(id)
  end
end
