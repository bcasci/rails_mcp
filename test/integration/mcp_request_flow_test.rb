# frozen_string_literal: true

require "test_helper"
# Force the mcp gem's lazily-autoloaded constants (notably MCP::ToolNotUnique) to be
# reachable when this file runs ALONE. `require "mcp"` loads the namespace; referencing
# MCP::Server in `setup` (below) triggers the autoload deterministically, so the
# ToolNotUnique assertion no longer depends on some earlier test having autoloaded it
# (spec 0011 R1, TEST-01).
require "mcp"
require_relative "fixture_app/boot"
require "rack/test"
require "json"
require "timeout"

# The single integration file for the /mcp HTTP request flow. A minimal but REAL Rails
# app (test/integration/fixture_app) boots the *rendered generator templates loaded
# verbatim* as its `McpController`, `ApplicationMcpTool`, `RegisteredTools`, and
# `ExampleReadOnlyTool`, under a real `ApplicationController` with
# `protect_from_forgery with: :exception` and a production Host in `config.hosts`. Every
# gap the unit tests miss (real CSRF, real production Host, a real ApplicationController,
# a redefined-class reload) is exercised end to end here.
#
# The verbatim rule: a test may not pass by diverging from the stamped code. Every stamped
# file the end-to-end call touches — the controller, the base tool, the allow-list, AND
# the example tool — is loaded byte-for-byte from its `.tt` and guarded by a
# source-equals-template test; the app wires the fail-closed seams only by SUBCLASSING and
# overriding, never by editing the verbatim source (spec 0005 R6, spec 0011 R2).
class McpRequestFlowTest < Minitest::Test
  include Rack::Test::Methods

  FixtureApp.load!

  StaffUser = Struct.new(:id, :name)
  ALICE = StaffUser.new(1, "Alice")
  BOB = StaffUser.new(2, "Bob")

  # The tool every HTTP proof exercises is the stamped `ExampleReadOnlyTool` the fixture
  # loads VERBATIM from `example_read_only_tool.rb.tt` and seeds into the verbatim
  # `RegisteredTools.all` — so every proof below runs through the byte-for-byte stamped
  # allow-list, not a stubbed stand-in. It advertises `example_read_only`, declares a
  # required `:subject` arg, and returns "Looked up: #{subject}".

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
    # Referencing MCP::Server here forces the mcp gem to autoload its lazily-loaded
    # constants (including MCP::ToolNotUnique) before any test asserts on them, so this
    # file's ToolNotUnique proof passes in isolation (R1, TEST-01).
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

  def post_mcp(method, params = {}, host: FixtureApp::PRODUCTION_HOST, id: 1, headers: {})
    Rack::MockRequest.new(app).post(
      "/mcp",
      {
        "HTTP_HOST" => host,
        "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json, text/event-stream",
        :input => JSON.generate(jsonrpc: "2.0", id: id, method: method, params: params)
      }.merge(headers)
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

  # R2 (spec 0011): the exercised ExampleReadOnlyTool IS the rendered
  # example_read_only_tool.rb.tt, verbatim — loaded the same way the other stamped files
  # are, not a const_set/hand-written stand-in. If the stamped example tool ever diverges
  # from what the fixture loaded, this fails: the HTTP proofs below cannot pass by
  # diverging from the generated example (spec 0011 R2, TEST-02).
  def test_example_read_only_tool_source_is_the_rendered_template_verbatim
    template = FixtureApp.template_source(FixtureApp::EXAMPLE_READ_ONLY_TOOL_TEMPLATE)

    assert ExampleReadOnlyTool < ApplicationMcpTool,
      "the loaded ExampleReadOnlyTool must subclass the verbatim ApplicationMcpTool"
    assert_includes template, "class ExampleReadOnlyTool < ApplicationMcpTool"
    assert_includes template, "arg :subject, :string, required: true"
    assert_equal template, File.read(FixtureApp::EXAMPLE_READ_ONLY_TOOL_TEMPLATE),
      "the exercised ExampleReadOnlyTool must be the rendered template, byte for byte"
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

  # ---- R2 the taught curl, end-to-end through the stamped allow-list ----------------

  # R2 (spec 0011, TEST-02): the exact `tools/call` body taught in README.md and
  # docs/USAGE.md §2a — `arguments: {subject: "first call"}` — posted cookieless through
  # the verbatim controller returns "Looked up: first call". The documented first call is
  # backed by a real request against the stamped example tool.
  def test_taught_curl_tools_call_returns_looked_up_first_call
    TestMcpController.resolver = ->(_req) { ALICE }

    call = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "first call"}})

    assert_equal 200, call.status
    assert_equal "Looked up: first call",
      JSON.parse(call.body).dig("result", "content", 0, "text")
  end

  # R7 (spec 0009): a real end-to-end tools/list + tools/call runs through the VERBATIM
  # controller and the VERBATIM RegisteredTools.all — the stamped artifact, not a stubbed
  # stand-in. tools/list advertises exactly the stamped list; tools/call on the seeded
  # tool (supplying the required :subject arg) returns its result.
  def test_end_to_end_tools_list_and_call_through_the_stamped_registered_tools
    TestMcpController.resolver = ->(_req) { ALICE }

    names = JSON.parse(post_mcp("tools/list").body).dig("result", "tools").map { |t| t["name"] }
    assert_equal ["example_read_only"], names,
      "tools/list must reflect the stamped RegisteredTools.all, exactly"

    call = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "widget"}})
    assert_equal 200, call.status
    assert_equal "Looked up: widget",
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

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "csrf"}})

    assert_equal 200, response.status, "cookieless POST must not be rejected by CSRF"
    assert_equal "Looked up: csrf",
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

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "host"}}, host: FixtureApp::PRODUCTION_HOST)

    refute_equal 403, response.status, "a config.hosts production Host must not be 403'd"
    refute_includes response.body, "Invalid Host header"
    assert_equal 200, response.status
  end

  # R2 (Host): the guard is genuinely on — a Host that is NEITHER loopback NOR in
  # config.hosts is rejected, proving the previous test's pass is the allow-list working,
  # not the guard being disabled.
  def test_unlisted_host_is_forbidden_proving_the_guard_is_active
    TestMcpController.resolver = ->(_req) { ALICE }

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "x"}}, host: "evil.example.com")

    assert_equal 403, response.status
    assert_includes response.body, "Invalid Host header"
  end

  # ---- spec 0013 R3 (SEC-03): empty-config.hosts must not 403 a real request -------

  # spec 0013 R3 (SEC-03): with `config.hosts` at its PRODUCTION DEFAULT — EMPTY of String
  # hosts, as a standard production app actually ships — the stamped controller sets
  # `dns_rebinding_protection: config.hosts.grep(String).any?` to false, so the SDK Host
  # guard is OFF and a real request is NOT 403'd. This is the day-one-outage case the
  # populated fixture masked: without the fix, empty config.hosts would fall back to
  # loopback-only and 403 every production request "Invalid Host header". The fixture must
  # NOT add the host here (SEC-03: test the stamped default at its production default, not a
  # test-populated value).
  def test_empty_config_hosts_does_not_403_a_real_request
    TestMcpController.resolver = ->(_req) { ALICE }

    FixtureApp.with_empty_config_hosts do
      assert_empty Rails.application.config.hosts.grep(String),
        "the empty-config case must run with NO String hosts — the production default"

      response = post_mcp(
        "tools/call",
        {name: "example_read_only", arguments: {subject: "empty-hosts"}},
        host: FixtureApp::PRODUCTION_HOST
      )

      refute_equal 403, response.status,
        "empty config.hosts must not 403 a real request — the guard is off, not loopback-only"
      refute_includes response.body, "Invalid Host header",
        "no Host-guard rejection when config.hosts is empty (guard off)"
      assert_equal 200, response.status,
        "the request must go through end to end with the guard off"
    end
  end

  # spec 0013 R3 (SEC-03): the guard flips back ON once config.hosts holds a String host
  # (`.any?` is true) — a foreign Host is then rejected AND the listed Host is accepted.
  # This is the populated counterpart to the empty-config case: it proves the fix ties the
  # guard to config.hosts rather than disabling it outright. The fixture seeds
  # PRODUCTION_HOST in boot, so this runs at the populated default.
  def test_populated_config_hosts_reenables_the_guard_rejecting_a_foreign_host
    assert Rails.application.config.hosts.grep(String).any?,
      "the populated case must run with config.hosts holding a String host (guard on)"
    TestMcpController.resolver = ->(_req) { ALICE }

    foreign = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "z"}}, host: "evil.example.com")
    assert_equal 403, foreign.status, "with hosts populated the guard is on — a foreign Host is 403'd"
    assert_includes foreign.body, "Invalid Host header"

    listed = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "z"}}, host: FixtureApp::PRODUCTION_HOST)
    assert_equal 200, listed.status, "the listed production Host is accepted with the guard on"
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
  # MCP::ToolNotUnique is a lazily-autoloaded mcp constant; this file's `require "mcp"` +
  # the MCP::Server reference in setup force it to load, so this passes in isolation (R1).
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

  # ---- R4 no-credential-leak on the real HTTP path (spec 0011, TEST-06) -------------

  # R4 (spec 0011): a tools/call carrying an `Authorization: Bearer <sentinel>` header
  # through the verbatim controller must leak the token in NEITHER the audit payload
  # (including the nested `:args`) NOR the HTTP response body. The gem never reads the
  # header; the app resolves it into a user, and only the user (not the raw token) rides
  # server_context. This is the no-credential-leak invariant on the REAL request path, not
  # against a hand-built payload hash.
  def test_bearer_token_leaks_into_neither_the_audit_payload_nor_the_http_body
    token = "SEKRET-BEARER-b3a1f9c2d4e5"
    # The seam resolves the header into a user WITHOUT ever putting the raw token on the
    # user or into args — the same shape a real app resolves (User.find_by(api_token:)).
    TestMcpController.resolver = lambda do |request|
      raw = request.get_header("HTTP_AUTHORIZATION").to_s
      raise RailsMcp::NotAuthorized, "no acting user" unless raw == "Bearer #{token}"

      ALICE
    end

    response = post_mcp(
      "tools/call",
      {name: "example_read_only", arguments: {subject: "leak-check"}},
      headers: {"HTTP_AUTHORIZATION" => "Bearer #{token}"}
    )

    assert_equal 200, response.status, "the bearer-authenticated call must succeed"
    refute_includes response.body, token,
      "the bearer token must not appear anywhere in the HTTP response body"

    payload = @events.last
    refute_nil payload, "the authenticated call must emit exactly one audit event"
    refute_includes JSON.generate(serializable(payload)), token,
      "the bearer token must not appear anywhere in the audit payload"
    refute_includes JSON.generate(payload[:args]), token,
      "the bearer token must not appear inside the nested payload[:args]"
  end

  # R4 (spec 0011): a tool whose `perform` raises surfaces a GENERIC JSON-RPC error
  # `message` ("Internal error"), never a backtrace or an HTML stack-trace page. The gem
  # is a neutral conduit (ADR-0012): the mcp gem — not this gem — owns the error surface,
  # and its default DOES place a developer-detail string in the JSON-RPC `error.data`
  # (`"Internal error calling tool <name>: <the raise message>"`). This test asserts the
  # real, verified behavior of the shipped stack, not a false "the raw message never
  # surfaces" claim: the raw message rides `error.data` and NOWHERE ELSE — the top-level
  # `error.message` stays generic, and no stack trace / HTML page leaks. An app that must
  # suppress `error.data` too configures the mcp gem's exception reporter itself; the gem
  # ships no such policy.
  def test_raising_perform_surfaces_a_generic_error_message_with_detail_only_in_error_data
    raw_message = "internal detail should not surface generically"
    raiser = Class.new(ApplicationMcpTool) do
      tool_name "raiser"
      description "A tool that raises (read-only)."
      read_only!
      define_singleton_method(:raise_message) { raw_message }
      def self.name = "FixtureApp::RaisingTool"
      def authorize(user:, args:, tool:) = (raise RailsMcp::NotAuthorized if user.nil?)
      def perform(**) = raise self.class.raise_message
    end
    TestMcpController.resolver = ->(_req) { ALICE }

    with_registered_tools([raiser]) do
      response = post_mcp("tools/call", {name: "raiser", arguments: {}})

      error = JSON.parse(response.body).fetch("error")
      assert_equal "Internal error", error["message"],
        "the surfaced top-level JSON-RPC error message must be generic, not the raw exception message"
      refute_includes error["message"].to_s, raw_message,
        "the generic top-level message must not carry the raw exception text"
      refute_includes response.body.downcase, "backtrace",
        "no backtrace is surfaced to the client"
      refute_includes response.body, "<html",
        "the surfaced error is a JSON-RPC error, not an HTML stack-trace page"

      # Where mcp places the developer detail in `error.data` is its own internal choice and
      # varies across `~> 1.1` (1.1.0 echoes the raw string there; 1.2.0 does not) — asserting
      # its presence pins a dependency internal, not this gem's guarantee. The guarantee, checked
      # above, is that the raw message never reaches the client-facing `error.message`. What we do
      # assert about `error.data` is the only security-relevant fact: whatever mcp puts there, it
      # is not an HTML page or a backtrace.
      data = error["data"].to_s
      refute_includes data.downcase, "backtrace",
        "no backtrace may surface in error.data either"
      refute_includes data, "<html",
        "error.data is structured JSON-RPC data, not an HTML stack-trace page"
    end
  end

  # ---- fail-closed (spec 0002 R2, no regression) -----------------------------------

  # spec 0002 R2 / R5: with the authentication seam left as stamped (fail-closed,
  # resolver nil), a request is denied — the seam raises before any tool runs, and no
  # audit event fires. No regression to the fail-closed default.
  def test_fail_closed_seam_denies_and_runs_no_tool
    TestMcpController.resolver = nil

    response = post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "denied"}})

    refute_equal 200, response.status, "an unwired seam must deny (fail closed)"
    refute_includes response.body, "Looked up:", "perform must not run"
    assert_empty @events, "no tool invocation, so no audit event fires"
  end

  # ---- R3 (spec 0011) interleaved-identity proof, migrated onto the verbatim fixture ---

  # R3 (spec 0011, TEST-03): two interleaved requests carrying DIFFERENT acting users do
  # not bleed identity. Migrated from the deleted hand-mirrored controller harness — the
  # Queue/barrier interleaving mechanism is preserved, but it now runs on the VERBATIM
  # fixture controller via `post_mcp`, and asserts each concurrent request's AUDIT PAYLOAD
  # carries only its own acting user. The per-request `server_context` is the isolation
  # boundary; a shared server would let one request's user reach the other's payload.
  def test_interleaved_requests_do_not_bleed_identity
    entered = Queue.new
    release = Queue.new
    barrier = -> {
      entered << :in
      release.pop
    }
    # A user-attributing tool served through the verbatim controller. It subclasses the
    # verbatim ApplicationMcpTool (the fixture's "subclass to wire seams" pattern), blocks
    # on the barrier so both requests genuinely overlap in perform, and stashes its own
    # request's user — which rides the audit payload the controller emits.
    echo_user = Class.new(ApplicationMcpTool) do
      tool_name "echo_user"
      description "Echo the acting user (read-only)."
      read_only!
      define_singleton_method(:barrier) { barrier }
      def self.name = "FixtureApp::EchoUserTool"

      def authorize(user:, args:, tool:)
        @acting_user = user
        raise RailsMcp::NotAuthorized, "no acting user" if user.nil?
      end

      def perform(**)
        self.class.barrier.call
        text_response("acting: #{@acting_user&.name}")
      end
    end

    # The seam resolves the user from a request header, so each concurrent request gets
    # its own — as a real controller resolves from its own auth stack per request.
    TestMcpController.resolver = lambda do |request|
      (request.get_header("HTTP_X_ACTING_USER") == "bob") ? BOB : ALICE
    end

    with_registered_tools([echo_user]) do
      results = {}
      threads = ["alice", "bob"].map do |name|
        Thread.new do
          resp = post_mcp(
            "tools/call",
            {name: "echo_user", arguments: {}},
            headers: {"HTTP_X_ACTING_USER" => name}
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

      # The audit payloads carry each request's own user, never the other's — the
      # per-request server_context did not bleed identity across the overlapping calls.
      users_by_name = @events.map { |p| p[:user] }
      assert_includes users_by_name, ALICE, "Alice's call must be attributed to Alice"
      assert_includes users_by_name, BOB, "Bob's call must be attributed to Bob"
    end
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

    post_mcp("tools/call", {name: "example_read_only", arguments: {subject: "keys"}})

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

  private

  # Temporarily swap the app-owned `RegisteredTools.all` list (the exact seam the stamped
  # controller documents as "yours to edit — swap in your own list") to serve a different
  # tool set through the VERBATIM controller for one test, then restore it. The controller
  # stays byte-for-byte verbatim; only the app-owned allow-list — meant to be edited — is
  # swapped, so the source-equals-template guard still holds afterward.
  def with_registered_tools(tools)
    original = RegisteredTools.method(:all)
    redefine_all { tools }
    yield
  ensure
    redefine_all(&original)
  end

  # Redefine `RegisteredTools.all` quietly. It is defined as `def self.all` in the verbatim
  # template, so any swap redefines an existing singleton method; silencing the redefinition
  # warning keeps the deliberate, app-owned list swap from spamming the suite output.
  def redefine_all(&block)
    warn_level = $VERBOSE
    $VERBOSE = nil
    RegisteredTools.singleton_class.send(:define_method, :all, &block)
  ensure
    $VERBOSE = warn_level
  end

  # A JSON-serializable view of the audit payload for a whole-payload substring scan. The
  # `user` is an app object (a Struct here); rendering its inspect string is enough to
  # prove the raw token appears nowhere in it.
  def serializable(payload)
    {
      user: payload[:user].inspect,
      tool: payload[:tool],
      args: payload[:args],
      result: payload[:result].inspect
    }
  end
end
