# frozen_string_literal: true

require "test_helper"
require "mcp"
require "rack"
require "rack/mock"
require "json"
require "timeout"
require "stringio"

# T0 / R1, R5 — `RailsMcp.serve` is the per-request entry point the generated
# controller calls to run ONE MCP request with a per-request acting user, isolating
# `server_context` per request (never mutating a shared, process-wide server). These
# tests drive `serve` directly with real Rack envs and a real `RailsMcp::Tool`
# subclass (no mocks of the unit under test), asserting on outcomes: the user that
# reaches `authorize` / the audit payload, the tool result on the Rack response, and
# no cross-request identity bleed under real concurrency.
class RailsMcp::ServeTest < Minitest::Test
  # A real staff-user stand-in. The gem never defines identity; the app hands one in.
  StaffUser = Struct.new(:id, :name)

  ALICE = StaffUser.new(1, "Alice")
  BOB = StaffUser.new(2, "Bob")

  def setup
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*, payload|
      @events << payload
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
  end

  # A tool whose perform echoes the acting user's name, so the Rack response and the
  # audit payload can both be checked. Overrides call to reach the user via authorize.
  def echo_tool(seen_users, before_perform: nil)
    Class.new(RailsMcp::Tool) do
      tool_name "echo_user"

      define_method(:authorize) do |user:, args:, tool:|
        seen_users << user
        # Stash on THIS instance so perform reads its own request's user, not a shared
        # last-writer — the invoke pipeline runs authorize + perform on one instance.
        @acting_user = user
        raise RailsMcp::NotAuthorized, "no user" if user.nil?
      end

      define_method(:perform) do |**_args|
        before_perform&.call
        text_response("acting: #{@acting_user&.name}")
      end
    end
  end

  def env_for(method, params = {}, id: 1, host: "example.org")
    body = JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
    Rack::MockRequest.env_for(
      "/",
      "REQUEST_METHOD" => "POST",
      "rack.input" => StringIO.new(body),
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "HTTP_HOST" => host
    )
  end

  def parse(triple)
    _status, _headers, body = triple
    chunks = []
    body.each { |c| chunks << c }
    JSON.parse(chunks.join)
  end

  # R1: the resolved `user:` reaches `authorize` and the audit payload, and the tool
  # result rides the Rack response.
  def test_serve_places_user_on_authorize_and_payload_and_returns_result
    seen = []
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool(seen)) }

    triple = RailsMcp.serve(
      env_for("tools/call", {name: "echo_user", arguments: {}}),
      user: ALICE,
      registry: registry,
      allowed_hosts: ["example.org"]
    )
    body = parse(triple)

    assert_same ALICE, seen.last, "the resolved user reaches authorize"
    assert_same ALICE, @events.last[:user], "the resolved user reaches the audit payload"
    assert_equal "acting: Alice", body.dig("result", "content", 0, "text")
  end

  # R1: `serve` returns a Rack response triple [status, headers, body].
  def test_serve_returns_a_rack_response_triple
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool([])) }

    triple = RailsMcp.serve(
      env_for("tools/list"),
      user: ALICE,
      registry: registry,
      allowed_hosts: ["example.org"]
    )

    assert_equal 3, triple.size
    status, headers, resp_body = triple
    assert_equal 200, status
    assert_kind_of Hash, headers
    assert_respond_to resp_body, :each
  end

  # R1 (thread-safety): two interleaved serve calls with different users each see only
  # their own user — no cross-request identity bleed. Real concurrency: perform blocks
  # on a barrier so both requests are in-flight at once, forcing overlap.
  def test_interleaved_requests_do_not_bleed_identity
    barrier = Queue.new
    gate = Queue.new
    seen = []

    # perform waits until both threads have entered, so the two invocations genuinely
    # overlap rather than running one-then-the-other.
    hold = -> {
      barrier << :in
      gate.pop
    }
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool(seen, before_perform: hold)) }

    results = {}
    threads = {ALICE => nil, BOB => nil}.keys.map do |user|
      Thread.new do
        triple = RailsMcp.serve(
          env_for("tools/call", {name: "echo_user", arguments: {}}),
          user: user,
          registry: registry,
          allowed_hosts: ["example.org"]
        )
        results[user] = parse(triple)
      end
    end

    # Wait (bounded) for both threads to be inside perform, so they overlap. Timeout
    # keeps a crashed thread from hanging the suite.
    Timeout.timeout(10) { 2.times { barrier.pop } }
    2.times { gate << :go }
    threads.each { |t| t.join(10) }

    assert_equal "acting: Alice", results[ALICE].dig("result", "content", 0, "text")
    assert_equal "acting: Bob", results[BOB].dig("result", "content", 0, "text")
  end

  # R5: a request with no resolved user fails closed — the app's authorize denies and
  # no tool result is returned.
  def test_serve_without_user_fails_closed
    seen = []
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool(seen)) }

    triple = RailsMcp.serve(
      env_for("tools/call", {name: "echo_user", arguments: {}}),
      user: nil,
      registry: registry,
      allowed_hosts: ["example.org"]
    )
    body = parse(triple)

    assert_instance_of RailsMcp::NotAuthorized, @events.last[:error]
    refute_equal "acting: ", body.dig("result", "content", 0, "text")
  end

  # R1: tools/list through serve returns only registered tools (allow-list parity with
  # the direct mount).
  def test_tools_list_through_serve_returns_only_registered_tools
    seen = []
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool(seen)) }

    triple = RailsMcp.serve(
      env_for("tools/list"),
      user: ALICE,
      registry: registry,
      allowed_hosts: ["example.org"]
    )
    names = parse(triple).dig("result", "tools").map { |t| t["name"] }

    assert_equal ["echo_user"], names
  end

  # R1 (R4/R9): the raw request/env and any bearer token never reach server_context or
  # the payload — only the resolved user does.
  def test_raw_request_and_token_never_reach_payload
    seen = []
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool(seen)) }
    env = env_for("tools/call", {name: "echo_user", arguments: {}})
    env["HTTP_AUTHORIZATION"] = "Bearer super-secret-token"

    RailsMcp.serve(env, user: ALICE, registry: registry, allowed_hosts: ["example.org"])

    serialized = @events.last.inspect
    refute_includes serialized, "super-secret-token", "the bearer token must not enter the payload"
    refute_includes serialized, "HTTP_AUTHORIZATION", "the raw env must not enter the payload"
    assert_equal [:user, :tool, :args, :result], @events.last.keys, "payload carries only the frozen keys"
  end

  # R1: serve accepts an ActionDispatch::Request-like object (anything exposing #env),
  # not only a raw Rack env Hash (tolerant input).
  def test_serve_accepts_an_object_exposing_env
    seen = []
    registry = RailsMcp::Registry.new.tap { |r| r.register(echo_tool(seen)) }
    request_like = Struct.new(:env).new(env_for("tools/call", {name: "echo_user", arguments: {}}))

    triple = RailsMcp.serve(request_like, user: BOB, registry: registry, allowed_hosts: ["example.org"])
    body = parse(triple)

    assert_equal "acting: Bob", body.dig("result", "content", 0, "text")
  end
end
