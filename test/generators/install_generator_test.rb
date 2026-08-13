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

  # R2: the resolve-acting-user → RailsMcp.serve flow is present as a marked,
  # editable point in the controller.
  def test_mcp_controller_serves_via_rails_mcp_serve
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb", /RailsMcp\.serve/
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

  # R11: the gem presumes no tenancy — scoping is a commented, optional note, never
  # active tenant code stamped by default.
  def test_no_active_tenant_code_stamped
    with_routes_file
    run_generator
    assert_file "app/mcp/application_mcp_tool.rb" do |content|
      code_lines = content.lines.reject { |l| l.strip.empty? || l.strip.start_with?("#") }
      refute(code_lines.any? { |l| l.include?("with_shard") },
        "no active tenant/shard code may be stamped (R11: no presumed tenancy)")
    end
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
