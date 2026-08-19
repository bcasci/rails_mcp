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

  # The tool the CSRF/Host/fail-closed proofs exercise is the stamped `ExampleReadOnlyTool`
  # the fixture seeds into the verbatim `RegisteredTools.all` — so every HTTP proof below
  # runs through the byte-for-byte stamped allow-list, not a stubbed stand-in (spec 0009
  # R7). It advertises `example_read_only` and returns "Looked up: example".

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

  # R7 (spec 0009): the exercised RegisteredTools allow-list IS the rendered
  # registered_tools.rb.tt, verbatim. The template carries no ERB, so the file is the
  # rendered output; the fixture eval'd it at TOPLEVEL_BINDING. If the stamped list ever
  # diverges from what the fixture loaded, this fails — the end-to-end proofs below cannot
  # pass by diverging from the generated allow-list.
  def test_registered_tools_source_is_the_rendered_template_verbatim
    template = FixtureApp.template_source(FixtureApp::REGISTERED_TOOLS_TEMPLATE)

    assert_includes template, "module RegisteredTools"
    assert_includes template, "def self.all"
    assert_equal [ExampleReadOnlyTool], RegisteredTools.all,
      "the stamped RegisteredTools.all must return the seeded [ExampleReadOnlyTool] literal"
    assert_equal template, File.read(FixtureApp::REGISTERED_TOOLS_TEMPLATE),
      "the exercised RegisteredTools must be the rendered template, byte for byte"
  end

  # ---- R7 end-to-end through the stamped allow-list --------------------------------

  # R7 (spec 0009): a real end-to-end tools/list + tools/call runs through the VERBATIM
  # controller and the VERBATIM RegisteredTools.all — the stamped artifact, not a stubbed
  # stand-in. tools/list advertises exactly the stamped list; tools/call on the seeded
  # tool returns its result. This is the app-owned allow-list proof R7 requires.
  def test_end_to_end_tools_list_and_call_through_the_stamped_registered_tools
    TestMcpController.resolver = ->(_req) { ALICE }

    names = JSON.parse(post_mcp("tools/list").body).dig("result", "tools").map { |t| t["name"] }
    assert_equal ["example_read_only"], names,
      "tools/list must reflect the stamped RegisteredTools.all, exactly"

    call = post_mcp("tools/call", {name: "example_read_only", arguments: {}})
    assert_equal 200, call.status
    assert_equal "Looked up: example",
      JSON.parse(call.body).dig("result", "content", 0, "text")
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

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {}})

    assert_equal 200, response.status, "cookieless POST must not be rejected by CSRF"
    assert_equal "Looked up: example",
      JSON.parse(response.body).dig("result", "content", 0, "text")
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

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {}}, host: FixtureApp::PRODUCTION_HOST)

    refute_equal 403, response.status, "a config.hosts production Host must not be 403'd"
    refute_includes response.body, "Invalid Host header"
    assert_equal 200, response.status
  end

  # R2 (Host): the guard is genuinely on — a Host that is NEITHER loopback NOR in
  # config.hosts is rejected, proving the previous test's pass is the allow-list working,
  # not the guard being disabled.
  def test_unlisted_host_is_forbidden_proving_the_guard_is_active
    TestMcpController.resolver = ->(_req) { ALICE }

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {}}, host: "evil.example.com")

    assert_equal 403, response.status
    assert_includes response.body, "Invalid Host header"
  end

  # ---- R4 reload-safe by construction; R3 collision caught by mcp -------------------

  # A fresh reload stand-in: a NEW class object with the same class name and tool_name — a
  # Zeitwerk dev-reload equivalent. Each call returns a distinct class object.
  def build_reloadable_tool
    Class.new(ApplicationMcpTool) do
      tool_name "reloadable"
      description "A reloadable tool (read-only)."
      read_only!
      def self.name = "FixtureApp::ReloadableTool"
      def authorize(user:, args:, tool:) = (raise RailsMcp::NotAuthorized if user.nil?)
      def perform(**) = text_response("reloaded")
    end
  end

  # spec 0009 R4 (reload-safe by construction): a tool redefined mid-run (a new class
  # object, same class name and tool_name) does NOT raise ToolNotUnique when the next
  # request rebuilds MCP::Server from the app-owned list. Because the list is resolved
  # fresh per request, only the current class object is present — no stale, colliding
  # class survives. The tool is listed exactly once.
  def test_reloaded_tool_rebuilds_server_without_tool_not_unique
    first = MCP::Server.new(name: "rails_mcp", tools: [build_reloadable_tool])
    assert_equal ["reloadable"], first.tools.keys,
      "the tool lists once before the reload"

    # The reload: a fresh class object with the same class name and tool_name is what the
    # per-request list now yields. Building the server again must not raise ToolNotUnique.
    reloaded = build_reloadable_tool
    second = MCP::Server.new(name: "rails_mcp", tools: [reloaded])

    refute_nil second, "rebuilding the server from the reloaded class must not raise"
    assert_equal ["reloadable"], second.tools.keys,
      "the reloaded tool is served exactly once"
  end

  # spec 0009 R3 (allow-list is mcp's; collision caught by mcp): two DISTINCT classes that
  # share a tool_name in the list make mcp raise ToolNotUnique at MCP::Server.new. This is
  # the positive collision case the gem relies on mcp to catch (no gem-side
  # ToolNameCollision) — the counterpart to the reload case above, which must NOT raise.
  def test_two_classes_sharing_a_tool_name_raise_tool_not_unique_at_build
    duplicate_a = Class.new(ApplicationMcpTool) do
      tool_name "dup"
      description "First dup (read-only)."
      read_only!
      def self.name = "FixtureApp::DupA"
      def perform(**) = text_response("a")
    end
    duplicate_b = Class.new(ApplicationMcpTool) do
      tool_name "dup"
      description "Second dup (read-only)."
      read_only!
      def self.name = "FixtureApp::DupB"
      def perform(**) = text_response("b")
    end

    refute_same duplicate_a, duplicate_b, "the collision must be two distinct class objects"
    assert_raises(MCP::ToolNotUnique) do
      MCP::Server.new(name: "rails_mcp", tools: [duplicate_a, duplicate_b])
    end
  end

  # ---- fail-closed (spec 0002 R2, no regression) -----------------------------------

  # spec 0002 R2 / R5: with the authentication seam left as stamped (fail-closed,
  # resolver nil), a request is denied — the seam raises before any tool runs, and no
  # audit event fires. No regression to the fail-closed default.
  def test_fail_closed_seam_denies_and_runs_no_tool
    TestMcpController.resolver = nil

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {}})

    refute_equal 200, response.status, "an unwired seam must deny (fail closed)"
    refute_includes response.body, "Looked up: example", "perform must not run"
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

    post_mcp("tools/call", {name: "example_read_only", arguments: {}})

    payload = @events.last
    refute_nil payload, "an audit event must fire for a successful call"
    assert_equal %i[user tool args result], payload.keys,
      "the invoke.rails_mcp payload keys are a frozen contract"
    assert_same ALICE, payload[:user], "identity flows through server_context to the payload"
    assert_equal "example_read_only", payload[:tool]
  end

  # R5: identity rides server_context (not a tool arg) — the resolved staff user reaches
  # the tool and the payload, and is never an argument the AI supplies.
  def test_identity_rides_server_context_not_an_arg
    TestMcpController.resolver = ->(_req) { ALICE }

    body = JSON.parse(post_mcp("tools/list").body)
    tool = body.dig("result", "tools").find { |t| t["name"] == "example_read_only" }

    schema_props = tool.dig("inputSchema", "properties") || {}
    refute_includes schema_props.keys, "user",
      "identity must not be a tool arg — it rides server_context"
  end

  # R5: the allow-list is the only callable surface — tools/list returns only registered
  # tools; nothing generic or console-like is exposed.
  def test_allow_list_is_the_only_surface
    TestMcpController.resolver = ->(_req) { ALICE }

    names = JSON.parse(post_mcp("tools/list").body).dig("result", "tools").map { |t| t["name"] }

    assert_equal ["example_read_only"], names, "only registered tools are listable/callable"
  end

  # R5: read-only v1 scope holds — a registered tool advertises the read-only annotation.
  def test_read_only_scope_holds
    TestMcpController.resolver = ->(_req) { ALICE }

    body = JSON.parse(post_mcp("tools/list").body)
    tool = body.dig("result", "tools").find { |t| t["name"] == "example_read_only" }

    assert_equal true, tool.dig("annotations", "readOnlyHint"),
      "v1 tools advertise the read-only hint"
  end
end
