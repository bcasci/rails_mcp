# frozen_string_literal: true

require "test_helper"
require_relative "fixture_app/boot"
require "rack/test"
require "json"

# T3 / spec 0005 R5, R6 — the verbatim-template integration proof. A minimal but REAL
# Rails app (test/integration/fixture_app) boots the *rendered generator templates loaded
# verbatim* as its `McpController` and `ApplicationMcpTool`, under a real
# `ApplicationController` with `protect_from_forgery with: :exception` and a production Host
# in `config.hosts`. Every gap the earlier tests missed (real CSRF, real production Host, a
# real ApplicationController, a redefined-class reload) is exercised end to end here.
#
# The R6 verbatim rule: a test may not pass by diverging from the stamped code. The base
# `McpController`/`ApplicationMcpTool` are loaded byte-for-byte from the `.tt` files and a
# guard test asserts the loaded source equals the template; the app wires the fail-closed
# seams only by SUBCLASSING and overriding, never by editing the verbatim source.
class RealWorldHardeningTest < Minitest::Test
  include Rack::Test::Methods

  FixtureApp.load!

  StaffUser = Struct.new(:id, :name)
  ALICE = StaffUser.new(1, "Alice")

  # A plain read-only tool for the CSRF/Host/reload/fail-closed proofs.
  class EchoTool < ApplicationMcpTool
    tool_name "echo"
    description "Echo a fixed string (read-only)."
    read_only!

    def authorize(user:, args:, tool:)
      raise RailsMcp::NotAuthorized, "no staff user" if user.nil?
    end

    def perform(**)
      text_response("echoed")
    end
  end

  # The app's controller: the VERBATIM base `McpController` with only the fail-closed
  # authentication seam overridden (as a developer would wire it). No edit to the base
  # source — the override lives on this subclass.
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
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(RailsMcp::Instrumentation::EVENT) do |*, payload|
      @events << payload
    end
    RegisteredTools.list = []
    TestMcpController.resolver = nil
    @app = nil
    route_to(TestMcpController)
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    RegisteredTools.list = []
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

  def post_mcp(method, params = {}, host: FixtureApp::PRODUCTION_HOST, id: 1)
    Rack::MockRequest.new(app).post(
      "/mcp",
      "HTTP_HOST" => host,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      :input => JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
    )
  end

  # ---- R6 verbatim guarantee -------------------------------------------------------

  # R6: the exercised McpController IS the rendered template. If the stamped controller
  # ever diverges from what this fixture loaded, this test fails — a test cannot pass by
  # diverging from the generated code.
  def test_mcp_controller_source_is_the_rendered_template_verbatim
    template = FixtureApp.template_source(FixtureApp::MCP_CONTROLLER_TEMPLATE)

    assert McpController < ApplicationController,
      "the loaded McpController must be the stamped ApplicationController subclass"
    assert_includes template, "class McpController < ApplicationController"
    assert_includes template, "skip_forgery_protection"
    assert_includes template, "allowed_hosts: Rails.application.config.hosts.grep(String)"
    # The base under test is the exact template file (no ERB, so file == rendered output).
    assert_equal template, File.read(FixtureApp::MCP_CONTROLLER_TEMPLATE),
      "the exercised McpController must be the rendered template, byte for byte"
  end

  # R6: the exercised ApplicationMcpTool IS the rendered template, verbatim.
  def test_application_mcp_tool_source_is_the_rendered_template_verbatim
    template = FixtureApp.template_source(FixtureApp::APPLICATION_MCP_TOOL_TEMPLATE)

    assert ApplicationMcpTool < RailsMcp::Tool,
      "the loaded ApplicationMcpTool must subclass RailsMcp::Tool"
    assert_includes template, "class ApplicationMcpTool < RailsMcp::Tool"
    assert_equal template, File.read(FixtureApp::APPLICATION_MCP_TOOL_TEMPLATE),
      "the exercised ApplicationMcpTool must be the rendered template, byte for byte"
  end

  # ---- R2 CSRF ---------------------------------------------------------------------

  # R2 (CSRF): a cookieless JSON POST with no CSRF token succeeds behind an
  # ApplicationController with `protect_from_forgery with: :exception`, because the stamped
  # controller calls skip_forgery_protection. Without the skip this would 422/raise
  # InvalidAuthenticityToken.
  def test_cookieless_post_succeeds_behind_protect_from_forgery_exception
    assert_equal ActionController::RequestForgeryProtection::ProtectionMethods::Exception,
      ApplicationController.forgery_protection_strategy,
      "the fixture ApplicationController must genuinely enforce CSRF (exception strategy)"
    TestMcpController.resolver = ->(_req) { ALICE }
    RegisteredTools.list = [EchoTool]

    response = post_mcp("tools/call", {name: "echo", arguments: {}})

    assert_equal 200, response.status, "cookieless POST must not be rejected by CSRF"
    assert_equal "echoed", JSON.parse(response.body).dig("result", "content", 0, "text")
  end

  # ---- R2 Host ---------------------------------------------------------------------

  # R2 (Host): a non-loopback production Host in config.hosts is NOT 403'd by the SDK
  # DNS-rebinding guard, because the stamped controller passes allowed_hosts from
  # config.hosts. The production host is genuinely non-loopback.
  def test_production_host_in_config_hosts_is_not_forbidden
    refute_includes ["127.0.0.1", "::1", "localhost"], FixtureApp::PRODUCTION_HOST,
      "the host under test must be genuinely non-loopback (loopback would pass trivially)"
    assert_includes Rails.application.config.hosts.grep(String), FixtureApp::PRODUCTION_HOST,
      "the production host must be in config.hosts so the guard can admit it"
    TestMcpController.resolver = ->(_req) { ALICE }
    RegisteredTools.list = [EchoTool]

    response = post_mcp("tools/call", {name: "echo", arguments: {}}, host: FixtureApp::PRODUCTION_HOST)

    refute_equal 403, response.status, "a config.hosts production Host must not be 403'd"
    refute_includes response.body, "Invalid Host header"
    assert_equal 200, response.status
  end

  # R2 (Host): the guard is genuinely on — a Host that is NEITHER loopback NOR in
  # config.hosts is rejected, proving the previous test's pass is the allow-list working,
  # not the guard being disabled.
  def test_unlisted_host_is_forbidden_proving_the_guard_is_active
    TestMcpController.resolver = ->(_req) { ALICE }
    RegisteredTools.list = [EchoTool]

    response = post_mcp("tools/call", {name: "echo", arguments: {}}, host: "evil.example.com")

    assert_equal 403, response.status
    assert_includes response.body, "Invalid Host header"
  end

  # ---- R1 reload -------------------------------------------------------------------

  # R1 (reload): a tool redefined mid-run (a new class object, same class name and
  # tool_name — a Zeitwerk reload stand-in) does not cause ToolNotUnique when the next
  # request builds the server; the tool is served exactly once.
  def test_redefined_tool_mid_run_does_not_raise_tool_not_unique
    TestMcpController.resolver = ->(_req) { ALICE }

    build_reloadable_tool = lambda do
      Class.new(ApplicationMcpTool) do
        tool_name "reloadable"
        description "A reloadable tool (read-only)."
        read_only!
        def self.name = "FixtureApp::ReloadableTool"
        def authorize(user:, args:, tool:) = (raise RailsMcp::NotAuthorized if user.nil?)
        def perform(**) = text_response("reloaded")
      end
    end

    RegisteredTools.list = [build_reloadable_tool.call]
    first = post_mcp("tools/list")
    assert_equal 200, first.status

    # Redefine (the reload): a NEW class object, same class name/tool_name, put back on the
    # app-owned list. The controller resolves `RegisteredTools.all` fresh per request, so the
    # server is rebuilt from the current class — no stale, colliding class object survives.
    RegisteredTools.list = [build_reloadable_tool.call]

    second = post_mcp("tools/list")
    assert_equal 200, second.status, "a reloaded tool must not raise ToolNotUnique"
    names = JSON.parse(second.body).dig("result", "tools").map { |t| t["name"] }
    assert_equal ["reloadable"], names, "the reloaded tool is served exactly once"
  end

  # ---- fail-closed (spec 0002 R2, no regression) -----------------------------------

  # spec 0002 R2 / R5: with the authentication seam left as stamped (fail-closed,
  # resolver nil), a request is denied — the seam raises before any tool runs, and no
  # audit event fires. No regression to the fail-closed default.
  def test_fail_closed_seam_denies_and_runs_no_tool
    TestMcpController.resolver = nil
    RegisteredTools.list = [EchoTool]

    response = post_mcp("tools/call", {name: "echo", arguments: {}})

    refute_equal 200, response.status, "an unwired seam must deny (fail closed)"
    refute_includes response.body, "echoed", "perform must not run"
    assert_empty @events, "no tool invocation, so no audit event fires"
  end

  # ---- R5 frozen contracts ---------------------------------------------------------

  # R5: the frozen authorize signature is unchanged — authorize(user:, args:, tool:).
  def test_authorize_signature_is_frozen
    params = ApplicationMcpTool.instance_method(:authorize).parameters
    assert_equal [%i[keyreq user], %i[keyreq args], %i[keyreq tool]], params,
      "authorize's frozen keyword signature must be user:, args:, tool:"
  end

  # R5: the invoke.rails_mcp audit payload keys are unchanged (user, tool, args, result).
  def test_audit_payload_keys_are_frozen
    TestMcpController.resolver = ->(_req) { ALICE }
    RegisteredTools.list = [EchoTool]

    post_mcp("tools/call", {name: "echo", arguments: {}})

    payload = @events.last
    refute_nil payload, "an audit event must fire for a successful call"
    assert_equal %i[user tool args result], payload.keys,
      "the invoke.rails_mcp payload keys are a frozen contract"
    assert_same ALICE, payload[:user], "identity flows through server_context to the payload"
    assert_equal "echo", payload[:tool]
  end

  # R5: identity rides server_context (not a tool arg) — the resolved staff user reaches
  # the tool and the payload, and is never an argument the AI supplies.
  def test_identity_rides_server_context_not_an_arg
    TestMcpController.resolver = ->(_req) { ALICE }
    RegisteredTools.list = [EchoTool]

    body = JSON.parse(post_mcp("tools/list").body)
    echo = body.dig("result", "tools").find { |t| t["name"] == "echo" }

    schema_props = echo.dig("inputSchema", "properties") || {}
    refute_includes schema_props.keys, "user",
      "identity must not be a tool arg — it rides server_context"
  end

  # R5: the allow-list is the only callable surface — tools/list returns only registered
  # tools; nothing generic or console-like is exposed.
  def test_allow_list_is_the_only_surface
    TestMcpController.resolver = ->(_req) { ALICE }
    RegisteredTools.list = [EchoTool]

    names = JSON.parse(post_mcp("tools/list").body).dig("result", "tools").map { |t| t["name"] }

    assert_equal ["echo"], names, "only registered tools are listable/callable"
  end

  # R5: read-only v1 scope holds — a registered tool advertises the read-only annotation.
  def test_read_only_scope_holds
    RegisteredTools.list = [EchoTool]
    TestMcpController.resolver = ->(_req) { ALICE }

    body = JSON.parse(post_mcp("tools/list").body)
    echo = body.dig("result", "tools").find { |t| t["name"] == "echo" }

    assert_equal true, echo.dig("annotations", "readOnlyHint"),
      "v1 tools advertise the read-only hint"
  end
end
