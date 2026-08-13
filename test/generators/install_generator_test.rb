# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/rails_mcp/install/install_generator"

# T6 / R7, R8, R9, R11 — the `rails g rails_mcp:install` generator stamps the
# app-owned, fail-closed seams: an `ApplicationMcpTool`, an initializer, the `/mcp`
# route line, one read-only example tool, and example tests. These run the real
# generator into a tmp destination and assert on the stamped files, per conventions
# (real objects, one behavior per test).
class InstallGeneratorTest < Rails::Generators::TestCase
  tests RailsMcp::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator", __dir__)
  setup :prepare_destination

  # A routes file must exist for the `route`/inject step to have something to edit.
  def with_routes_file
    mkdir_p "#{destination_root}/config"
    File.write("#{destination_root}/config/routes.rb", "Rails.application.routes.draw do\nend\n")
  end

  # R8: the generator creates the app-owned ApplicationMcpTool under app/mcp/.
  def test_creates_application_mcp_tool
    with_routes_file
    run_generator
    assert_file "app/mcp/application_mcp_tool.rb", /class ApplicationMcpTool < RailsMcp::Tool/
  end

  # R8: the generator creates the initializer at the DECIDED path.
  def test_creates_initializer
    with_routes_file
    run_generator
    assert_file "config/initializers/rails_mcp.rb"
  end

  # spec 0004 R3: the generated default registers centrally in the initializer;
  # `expose!` is an alternative, not the generated default. Guards against a future
  # change that quietly makes co-located `expose!` the stamped default.
  def test_default_registration_is_central_not_expose
    with_routes_file
    run_generator
    assert_file "config/initializers/rails_mcp.rb", /RailsMcp\.registry\.register\(/
    assert_file "app/mcp/example_read_only_tool.rb" do |content|
      refute_match(/expose!/, content,
        "the generated example tool must register centrally, not via expose!")
    end
  end

  # R8: the generator creates one read-only example tool.
  def test_creates_example_read_only_tool
    with_routes_file
    run_generator
    assert_file "app/mcp/example_read_only_tool.rb", /read_only!/
  end

  # R8: the example tool subclasses the app-owned ApplicationMcpTool (inherits seams).
  def test_example_tool_subclasses_application_mcp_tool
    with_routes_file
    run_generator
    assert_file "app/mcp/example_read_only_tool.rb", /< ApplicationMcpTool/
  end

  # R8: the generator creates example tests.
  def test_creates_example_tests
    with_routes_file
    run_generator
    assert_file "test/mcp/example_read_only_tool_test.rb"
  end

  # R3: the generator routes `/mcp` to McpController for the MCP request verbs.
  def test_routes_mcp_to_controller
    with_routes_file
    run_generator
    assert_file "config/routes.rb", /["']mcp#/
  end

  # R3: the direct `mount_mcp '/mcp'` line is no longer stamped — the generated
  # default routes through the controller (ADR-0006).
  def test_does_not_stamp_direct_mount_mcp_line
    with_routes_file
    run_generator
    assert_file "config/routes.rb" do |content|
      refute_match(/mount_mcp ["']\/mcp["']/, content,
        "the direct mount_mcp '/mcp' line must not be stamped (routed via McpController instead)")
    end
  end

  # R3: the route dispatches all MCP request verbs the stateless transport uses
  # (POST, GET, DELETE) to the controller action — no verb the prior direct mount
  # served is dropped.
  def test_route_covers_mcp_request_verbs
    with_routes_file
    run_generator
    assert_file "config/routes.rb" do |content|
      assert_match(/:get/, content, "GET must reach the controller action")
      assert_match(/:post/, content, "POST must reach the controller action")
      assert_match(/:delete/, content, "DELETE must reach the controller action")
    end
  end

  # R2: the generator creates an app-owned McpController < ApplicationController.
  def test_creates_mcp_controller
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb",
      /class McpController < ApplicationController/
  end

  # R2: the controller is fail-closed by default — its authentication seam raises
  # until the implementor wires real auth, mirroring ApplicationMcpTool#authorize.
  def test_mcp_controller_is_fail_closed
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/raise/, content, "stamped authentication seam must fail closed (raise)")
    end
  end

  # R1: the controller builds the server on the `mcp` gem's public per-request
  # pattern — a fresh MCP::Server from the registry's tools.
  def test_mcp_controller_builds_server_on_public_mcp_api
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/MCP::Server\.new/, content, "controller must build a fresh MCP::Server")
      assert_match(/RailsMcp\.registry\.tools/, content,
        "the server's tool set must be RailsMcp.registry.tools (the allow-list)")
    end
  end

  # R1: the controller serves via the public StreamableHTTPTransport#handle_request,
  # passing the request and rendering the returned Rack triple.
  def test_mcp_controller_serves_via_handle_request
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/StreamableHTTPTransport\.new/, content,
        "controller must build the streamable-HTTP transport")
      assert_match(/handle_request\(request\)/, content,
        "controller must serve the request via handle_request")
    end
  end

  # R1: the acting user rides server_context at construction (per-request identity),
  # never by mutating a shared server.
  def test_mcp_controller_sets_user_on_server_context
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb",
      /server_context:\s*\{\s*user:\s*user\s*\}/
  end

  # R1: the controller references no removed gem entry point and no `mcp` private
  # reach — only public `mcp` API and RailsMcp.registry.tools.
  def test_mcp_controller_uses_no_removed_or_private_api
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      refute_match(/RailsMcp\.serve/, content, "no RailsMcp.serve — it is removed")
      refute_match(/instance_variable_get/, content, "no `mcp` private reach")
      refute_match(/mount_mcp/, content, "no mount_mcp — it is removed")
    end
  end

  # R2/R4: the authentication seam is a clearly marked, commented editable point
  # pointing the implementor at their own auth stack.
  def test_mcp_controller_has_marked_auth_seam
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/AUTHENTICAT/i, content, "the authentication seam must be clearly marked")
      assert_match(/^\s*#.*(Devise|session|token|auth)/i, content,
        "a comment must point the implementor at their own auth stack")
    end
  end

  # R4: the generated controller states the /mcp endpoint is unauthenticated until
  # secured.
  def test_mcp_controller_carries_secure_this_notice
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb", /unauthenticated until/i
  end

  # R4: the generator's post-run output includes the "unauthenticated until you
  # secure McpController" notice, naming the file.
  def test_generator_output_carries_security_notice
    with_routes_file
    output = run_generator
    assert_match(/unauthenticated/i, output,
      "post-run output must warn the /mcp endpoint is unauthenticated")
    assert_match(/mcp_controller\.rb|McpController/, output,
      "post-run notice must name the McpController file")
  end

  # R2 (CSRF): the stamped controller calls skip_forgery_protection so a cookieless
  # JSON POST from a machine client is not rejected with InvalidAuthenticityToken
  # under an ApplicationController with `protect_from_forgery with: :exception`.
  def test_mcp_controller_skips_forgery_protection
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb", /^\s*skip_forgery_protection\b/
  end

  # R2 (Host): the stamped controller passes allowed_hosts: from the app's host
  # allow-list so a non-loopback production Host in config.hosts is not 403'd by the
  # SDK DNS-rebinding guard.
  def test_mcp_controller_passes_allowed_hosts_from_config
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb",
      /allowed_hosts:\s*Rails\.application\.config\.hosts/
  end

  # R2 (Host): only String entries of config.hosts are passed — the guard down-cases
  # entries and cannot compare a Regexp/IPAddr, so the template filters to strings.
  def test_mcp_controller_filters_config_hosts_to_strings
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb",
      /Rails\.application\.config\.hosts\.grep\(String\)/
  end

  # R2 (auth filters): the controller carries a marked comment guiding the app to
  # skip_before_action any inherited browser auth filter that would 302-redirect a
  # machine client.
  def test_mcp_controller_guides_skip_before_action_for_browser_auth
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/skip_before_action/, content,
        "controller must guide skipping inherited browser auth before_actions")
      assert_match(/302|redirect/i, content,
        "the guidance must explain a browser auth filter would redirect a machine client")
    end
  end

  # R2 (inheritance comment): the inheritance comment no longer implies the app's
  # before_action stack works unchanged for this token endpoint.
  def test_mcp_controller_inheritance_comment_corrected
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/machine endpoint/i, content,
        "the inheritance comment must mark this as a machine (not browser) endpoint")
      refute_match(/reuses YOUR app's existing auth stack/i, content,
        "the inheritance comment must not imply the app's auth stack works unchanged")
    end
  end

  # R2: the controller documents the neutral pipeline-ordering fact — authorize runs
  # before perform, and a whole-call request-scoped context wraps handle_request.
  def test_mcp_controller_documents_neutral_request_scope_fact
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/`authorize`.*before.*`perform`/i, content,
        "controller must document that authorize runs before perform")
      assert_match(/wrap `handle_request`/i, content,
        "controller must document wrapping handle_request to scope the whole call")
    end
  end

  # R2: the neutral fact carries no tenancy words — no tenant/shard/Current.tenant.
  def test_mcp_controller_carries_no_tenancy_words
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      refute_match(/tenant/i, content, "no tenant word may appear in the stamped controller")
      refute_match(/shard/i, content, "no shard word may appear in the stamped controller")
      refute_match(/multitenan/i, content, "no multitenancy word may appear in the stamped controller")
    end
  end

  # R7: the stamped ApplicationMcpTool is fail-closed — it does not silently permit.
  # It must raise/deny in its stamped authorize seam rather than allow.
  def test_application_mcp_tool_is_fail_closed
    with_routes_file
    run_generator
    assert_file "app/mcp/application_mcp_tool.rb" do |content|
      assert_match(/def authorize/, content, "authorize seam must be present")
      assert_match(/raise/, content, "stamped authorize must fail closed (raise/deny)")
    end
  end

  # R7: the authorize and audit seams are present as clearly marked editable points.
  def test_application_mcp_tool_has_marked_seams
    with_routes_file
    run_generator
    assert_file "app/mcp/application_mcp_tool.rb" do |content|
      assert_match(/authorize/, content, "authorize seam marked")
      assert_match(/invoke\.rails_mcp/, content, "audit event name referenced for the audit seam")
    end
  end

  # R9: authorize uses the frozen `authorize(user:, args:, tool:)` signature so the
  # acting staff user is available to the seam.
  def test_authorize_seam_uses_frozen_signature
    with_routes_file
    run_generator
    assert_file "app/mcp/application_mcp_tool.rb", /def authorize\(user:, args:, tool:\)/
  end

  # R8: the example tests express authorization denial and audit-row-written as the
  # expected safety checks.
  def test_example_tests_express_authz_denial_and_audit
    with_routes_file
    run_generator
    assert_file "test/mcp/example_read_only_tool_test.rb" do |content|
      assert_match(/NotAuthorized|denied|denial|authorize/i, content,
        "example test must express authorization denial")
      assert_match(/invoke\.rails_mcp|audit|subscribe/i, content,
        "example test must express audit-row-written")
    end
  end
end
