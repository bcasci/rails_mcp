# frozen_string_literal: true

require "test_helper"
# Force the mcp gem's lazily-autoloaded constants reachable when this file runs
# ALONE: `require "mcp"` loads the namespace, and referencing MCP::Server in setup
# triggers the autoload deterministically (TEST-01), so nothing here depends on an
# earlier test having autoloaded an mcp constant.
require "mcp"
require_relative "fixture_app/boot"
require "rack/test"
require "json"

# Pins every documentation claim spec 0012 corrects to the behavior the shipped code
# actually produces, by POSTing the EXACT documented request against the verbatim
# rendered-template fixture (`test/integration/fixture_app`) — never a stubbed
# stand-in (spec 0012 DECIDED, spec 0005 R6 / spec 0009 R7). Each test drives the
# real /mcp HTTP flow through the byte-for-byte stamped `McpController`,
# `ApplicationMcpTool`, `RegisteredTools`, and `ExampleReadOnlyTool` the fixture loads,
# so a corrected doc and the shipped code can never silently diverge again:
#
#   * DOC-01 / R1  — a lone `tools/call` with NO prior `initialize` succeeds (stateless).
#   * ARCH-03 / R3 — an mcp-schema-rejected `tools/call` fires ZERO audit events.
#   * DOC-04 / R4  — the deny / raise / schema-reject client-facing wire surface.
#   * DOC-05 / R5  — the taught curl body returns "Looked up: first call".
class DocsAccuracyTest < Minitest::Test
  include Rack::Test::Methods

  FixtureApp.load!

  StaffUser = Struct.new(:id, :name)
  ALICE = StaffUser.new(1, "Alice")

  # The app's controller: the VERBATIM base `McpController` with only the fail-closed
  # authentication seam overridden, exactly as a developer wires it. The base source is
  # never edited — the override lives on this subclass (spec 0005 R6).
  class TestMcpController < McpController
    @resolver = nil
    class << self
      attr_accessor :resolver
    end

    private

    def authenticate_acting_user!
      resolver = self.class.resolver
      raise RailsMcp::NotAuthorized, "unauthenticated until secured" if resolver.nil?

      resolver.call(request)
    end
  end

  def app
    @app || Rails.application
  end

  def setup
    # Referencing MCP::Server forces the mcp gem to autoload its lazily-loaded
    # constants before any assertion, so this file passes in isolation (TEST-01).
    MCP.const_defined?(:Server) && MCP::Server

    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*, payload|
      @events << payload
    end
    TestMcpController.resolver = nil
    @app = nil
    route_to(TestMcpController)
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    TestMcpController.resolver = nil
    route_to(TestMcpController)
  end

  # Point the fixture app's /mcp route at the given controller for this test.
  def route_to(controller_class)
    name = controller_class.name.underscore.delete_suffix("_controller")
    Rails.application.routes.disable_clear_and_finalize = false
    Rails.application.routes.draw do
      match "/mcp", to: "#{name}#handle", via: [:get, :post, :delete]
    end
  end

  def post_mcp(method, params = {}, id: 1)
    Rack::MockRequest.new(app).post(
      "/mcp",
      {
        "HTTP_HOST" => FixtureApp::PRODUCTION_HOST,
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json, text/event-stream",
        :input => JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
      }
    )
  end

  # ---- DOC-01 / R1 : stateless first call, no prior initialize ----------------------

  # DOC-01 / R1: with the shipped `stateless: true` controller, each POST is
  # independent and self-contained — a lone `tools/call` with NO prior `initialize`
  # succeeds and returns a tool result, not a "Server not initialized" error. This
  # proves the documented stateless first-call the README/USAGE now state (and that the
  # deleted ordered-handshake note described an error the transport cannot emit).
  def test_lone_tools_call_without_initialize_succeeds
    TestMcpController.resolver = ->(_req) { ALICE }

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "first call"}})

    assert_equal 200, response.status,
      "a lone stateless tools/call must succeed with no prior initialize"
    body = JSON.parse(response.body)
    refute body.key?("error"),
      "the stateless first call must not be a JSON-RPC error (no initialize handshake required)"
    assert_equal false, body.dig("result", "isError"),
      "the stateless first call returns a tool result, not an error"
    assert_equal "Looked up: first call", body.dig("result", "content", 0, "text"),
      "the lone tools/call runs end to end through the stamped tool"
  end

  # ---- ARCH-03 / R3 : schema rejection fires no audit event -------------------------

  # ARCH-03 / R3: a `tools/call` for a REAL registered tool with a MISSING required
  # argument is rejected by the mcp gem at schema validation, BEFORE it reaches
  # `RailsMcp::Tool.call` — so ZERO `invoke.rails_mcp` events fire while the response is
  # an mcp-level error (isError: true). This pins the audit boundary the corrected
  # "exactly one event per invocation that reaches the pipeline" claim scopes.
  def test_schema_rejected_tools_call_fires_no_audit_event
    TestMcpController.resolver = ->(_req) { ALICE }

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {}})

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal true, body.dig("result", "isError"),
      "a missing required arg is an mcp-level error surfaced before the pipeline"
    assert_empty @events,
      "a schema-rejected call never reaches Tool.call, so no invoke.rails_mcp event fires"
  end

  # ---- DOC-04 / R4 : the client-facing deny / raise / schema-reject surface ---------

  # DOC-04 / R4 (a) denial: an `authorize` raising `RailsMcp::NotAuthorized` surfaces to
  # the client as mcp's `"Internal error calling tool <name>: <message>"` wrapper, and
  # its ONE `invoke.rails_mcp` audit event STILL fires (carrying the exception in
  # `error:`) — the denial reaches the pipeline, unlike a schema rejection.
  def test_denial_surfaces_documented_error_and_still_fires_one_audit_event
    # The wired authorize seam denies when the resolved user is nil (fail-closed).
    TestMcpController.resolver = ->(_req) {}

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "denied"}})

    assert_equal 200, response.status
    assert_includes response.body, "Internal error calling tool ",
      "a denial surfaces as mcp's Internal-error wrapper"
    refute_includes response.body, "Looked up:",
      "perform must not run when authorize denies"
    assert_equal 1, @events.size,
      "the denial reaches the pipeline, so its one audit event still fires"
    assert_instance_of RailsMcp::NotAuthorized, @events.last[:error],
      "the audit event records the denial exception in its error: payload"
  end

  # DOC-04 / R4 (b) raise: a `perform` raise surfaces to the client as mcp's
  # `"Internal error calling tool <name>: …"` wrapper (in the JSON-RPC error body), and
  # the one audit event records the exception — the corrected raise wording (no message
  # fidelity promise; the audit event carries the exception).
  def test_perform_raise_surfaces_the_internal_error_wrapper_and_records_the_exception
    TestMcpController.resolver = ->(_req) { ALICE }
    raiser = Class.new(ApplicationMcpTool) do
      tool_name "raiser"
      description "A tool that raises (read-only)."
      read_only!
      def self.name = "FixtureApp::DocsRaisingTool"
      def authorize(user:, args:, tool:) = (raise RailsMcp::NotAuthorized if user.nil?)
      def perform(**) = raise "internal boom"
    end

    with_registered_tools([raiser]) do
      response = post_mcp("tools/call", {name: "raiser", arguments: {}})

      assert_equal 200, response.status
      assert_includes response.body, "Internal error calling tool ",
        "a perform raise surfaces to the client as mcp's Internal-error wrapper"
      assert_equal 1, @events.size, "the raise reached the pipeline, so one audit event fires"
      assert_instance_of RuntimeError, @events.last[:error],
        "the audit event records the raised exception in its error: payload"
    end
  end

  # DOC-04 / R4 (c) schema rejection: a missing required arg returns an mcp-level error
  # (isError: true) with NO audit event — the pre-pipeline short-circuit the SEAMS.md
  # "What the client receives" subsection documents.
  def test_schema_rejection_returns_mcp_level_error_with_no_event
    TestMcpController.resolver = ->(_req) { ALICE }

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {}})

    body = JSON.parse(response.body)
    assert_equal true, body.dig("result", "isError"),
      "a schema rejection is an mcp-level error returned before the pipeline"
    refute_includes response.body, "Internal error calling tool ",
      "a schema rejection is not the pipeline raise wrapper — it short-circuits earlier"
    assert_empty @events, "no pipeline entry, so no audit event fires"
  end

  # ---- DOC-05 / R5 : the taught curl happy-path -------------------------------------

  # DOC-05 / R5: the EXACT README/USAGE curl body — `params: {name: "example_read_only",
  # arguments: {subject: "first call"}}` — POSTed against the verbatim fixture controller
  # returns result content `"Looked up: first call"` with `isError: false`. It drives the
  # tool loaded byte-for-byte from `example_read_only_tool.rb.tt` (required `arg :subject`,
  # echoing `subject`) — the fixture loads it verbatim, so this never depends on a stubbed
  # stand-in nor on the TEST-02 convergence landing first (spec 0012 R5).
  def test_taught_curl_body_returns_looked_up_first_call
    TestMcpController.resolver = ->(_req) { ALICE }

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "first call"}}, id: 3)

    assert_equal 200, response.status
    body = JSON.parse(response.body)
    assert_equal false, body.dig("result", "isError"),
      "the taught happy-path curl returns a successful tool result"
    assert_equal "Looked up: first call", body.dig("result", "content", 0, "text"),
      "the documented curl body returns the documented result against real code"
  end

  private

  # Temporarily swap the app-owned `RegisteredTools.all` list (the seam the stamped
  # controller documents as "yours to edit") to serve a test tool through the VERBATIM
  # controller, then restore it. The controller stays byte-for-byte verbatim; only the
  # app-owned allow-list is swapped, so the source-equals-template guard still holds.
  def with_registered_tools(tools)
    original = RegisteredTools.method(:all)
    redefine_all { tools }
    yield
  ensure
    redefine_all(&original)
  end

  # Redefine `RegisteredTools.all` quietly — it is `def self.all` in the verbatim
  # template, so any swap redefines an existing singleton method; silencing the
  # redefinition warning keeps the deliberate, app-owned list swap from spamming output.
  def redefine_all(&block)
    warn_level = $VERBOSE
    $VERBOSE = nil
    RegisteredTools.singleton_class.send(:define_method, :all, &block)
  ensure
    $VERBOSE = warn_level
  end
end
