# frozen_string_literal: true

require "test_helper"
require "action_controller"
require "action_dispatch"
require "rack/test"
require "json"
require "timeout"

# T2 / R2, R4, R5 integrated — the end-to-end proof for spec 0002's generated entry
# point: a request routed through an `McpController` equivalent to the stamped template
# (`lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt`) reaches
# `RailsMcp.serve`, so a fresh install is securable end to end.
#
# This exercises GENERATOR-SHAPED code, not a bespoke harness: the controller below
# mirrors the template line-for-line — a single `handle` action that calls a fail-closed
# `authenticate_acting_user!` seam, then `RailsMcp.serve(request, user:)`, rendering the
# Rack triple back through the controller's response. The route matches the stamped
# `routes_mount.rb.tt` (`/mcp` -> `mcp#handle` via GET/POST/DELETE). Real objects
# throughout; the only stub is the app-side staff identity the gem never defines.
class ControllerEndToEndTest < Minitest::Test
  include Rack::Test::Methods

  # A real staff-user stand-in. The gem never defines identity; the app resolves one.
  StaffUser = Struct.new(:id, :name)

  ALICE = StaffUser.new(1, "Alice")
  BOB = StaffUser.new(2, "Bob")

  # The read-only tool the app registers. Echoes the acting user so both the HTTP
  # response and the audit payload can be checked for correct per-request attribution.
  # authorize stashes the request's own user on THIS instance; the invoke pipeline runs
  # authorize + perform on one instance, so perform reads its own request's user.
  class EchoUserTool < RailsMcp::Tool
    tool_name "echo_user"
    description "Echo the acting user (read-only)."
    read_only!

    # A test barrier so two requests can be forced to overlap in-flight (thread-safety
    # criterion). Nil in the ordinary tests; set only for the interleaving test.
    class << self
      attr_accessor :perform_barrier
    end

    def authorize(user:, args:, tool:)
      @acting_user = user
      raise RailsMcp::NotAuthorized, "no staff user" if user.nil?
    end

    def perform(**)
      self.class.perform_barrier&.call
      text_response("acting: #{@acting_user&.name}")
    end
  end

  # The generated McpController template, mirrored as a real controller. `handle` is the
  # single action every MCP verb routes to; `authenticate_acting_user!` is the fail-closed
  # seam. `@@resolver` lets a test wire the seam (return a user) or leave it stamped
  # (raise) — standing in for the developer editing the template.
  class McpController < ActionController::Base
    @@resolver = nil

    def self.resolver=(callable)
      @@resolver = callable
    end

    def handle
      user = authenticate_acting_user!

      status, headers, body = RailsMcp.serve(request, user: user, registry: REGISTRY, allowed_hosts: ["example.org"])

      headers.each { |key, value| response.headers[key] = value }
      self.response_body = body
      self.status = status
    end

    private

    # === AUTHENTICATION SEAM (fail-closed by default) =====================
    # As stamped this RAISES (the template's default), so the endpoint denies until a
    # developer wires real auth. A test sets `resolver` to simulate that wiring.
    def authenticate_acting_user!
      raise RailsMcp::NotAuthorized, "unauthenticated until secured" if @@resolver.nil?

      @@resolver.call(request)
    end
  end

  # The allow-list: only EchoUserTool is registered, so only it is callable (parity with
  # the direct mount). No console/arbitrary-Ruby tool exists in the surface.
  REGISTRY = RailsMcp::Registry.new.tap { |r| r.register(EchoUserTool) }

  # A minimal Rails routing app: `/mcp` -> `mcp#handle` for the MCP verbs, mirroring the
  # stamped routes_mount.rb.tt. rack-test drives this, so requests genuinely pass through
  # the router and the controller action.
  ROUTES = ActionDispatch::Routing::RouteSet.new.tap do |routes|
    routes.draw do
      match "/mcp", to: "controller_end_to_end_test/mcp#handle", via: [:get, :post, :delete]
    end
  end

  # Wrap the router in the exception-showing middleware a real Rails app runs, so an
  # unrescued fail-closed raise from the seam becomes an HTTP denial (a 500), not a
  # crash — exactly as the stamped controller behaves behind ApplicationController.
  APP = ActionDispatch::ShowExceptions.new(ROUTES, ActionDispatch::PublicExceptions.new("/tmp"))

  def app
    APP
  end

  def setup
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*, payload|
      @events << payload
    end
    McpController.resolver = nil
    EchoUserTool.perform_barrier = nil
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    McpController.resolver = nil
    EchoUserTool.perform_barrier = nil
  end

  def json_rpc(method, params = {}, id: 1)
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    # Turn an unrescued fail-closed raise into an HTTP denial rather than a crash, as a
    # booted Rails app does at its exception boundary.
    env "action_dispatch.show_exceptions", :all
    env "action_dispatch.show_detailed_exceptions", false
    post "/mcp", JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
    last_response
  end

  # R2/R4/R5: with the authentication seam left as stamped (fail-closed), a request to
  # /mcp is denied — the seam raises before RailsMcp.serve, so no tool runs and no audit
  # event fires. The endpoint denies rather than exposes until secured.
  def test_fail_closed_before_auth_is_wired_no_tool_runs
    response = json_rpc("tools/call", {name: "echo_user", arguments: {}})

    refute response.successful?, "an unwired seam must deny (fail closed)"
    refute_includes response.body, "acting: Alice", "perform must not run"
    assert_empty @events, "no tool invocation, so no audit event fires"
  end

  # R2/R5: once the seam resolves staff user U, a tool invoked through the controller
  # runs and is attributed to U in the audit payload and in the HTTP result.
  def test_after_auth_wired_call_is_attributed_to_the_staff_user
    McpController.resolver = ->(_request) { ALICE }

    body = JSON.parse(json_rpc("tools/call", {name: "echo_user", arguments: {}}).body)

    assert_equal "acting: Alice", body.dig("result", "content", 0, "text")
    assert_same ALICE, @events.last[:user], "the resolved user reaches the audit payload"
    assert_equal "echo_user", @events.last[:tool]
  end

  # R3 (allow-list parity): tools/list through the routed controller returns only
  # registered tools.
  def test_tools_list_through_the_controller_returns_only_registered_tools
    McpController.resolver = ->(_request) { ALICE }

    body = JSON.parse(json_rpc("tools/list").body)
    names = body.dig("result", "tools").map { |t| t["name"] }

    assert_equal ["echo_user"], names
  end

  # R1/R5 (thread-safety, end-to-end): two interleaved requests carrying different users
  # do not bleed identity. Real overlap: perform blocks on a barrier until both requests
  # are in-flight, then both proceed; each response must carry only its own user.
  def test_interleaved_requests_do_not_bleed_identity
    entered = Queue.new
    release = Queue.new
    EchoUserTool.perform_barrier = -> {
      entered << :in
      release.pop
    }
    # The seam resolves the user from a request header, so each concurrent request gets
    # its own — as a real controller would resolve from its own auth stack per request.
    McpController.resolver = ->(request) {
      (request.get_header("HTTP_X_ACTING_USER") == "bob") ? BOB : ALICE
    }

    results = {}
    threads = [["alice", ALICE], ["bob", BOB]].map do |name, _user|
      Thread.new do
        req = Rack::MockRequest.new(APP)
        resp = req.post(
          "/mcp",
          "CONTENT_TYPE" => "application/json",
          "HTTP_ACCEPT" => "application/json, text/event-stream",
          "HTTP_X_ACTING_USER" => name,
          "action_dispatch.show_exceptions" => :all,
          :input => JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call",
            params: {name: "echo_user", arguments: {}})
        )
        results[name] = JSON.parse(resp.body)
      end
    end

    # Wait (bounded) for both requests to be inside perform, so they genuinely overlap,
    # then release both. Timeout keeps a crashed thread from hanging the suite.
    Timeout.timeout(10) { 2.times { entered.pop } }
    2.times { release << :go }
    threads.each { |t| t.join(10) }

    assert_equal "acting: Alice", results["alice"].dig("result", "content", 0, "text")
    assert_equal "acting: Bob", results["bob"].dig("result", "content", 0, "text")
  end
end
