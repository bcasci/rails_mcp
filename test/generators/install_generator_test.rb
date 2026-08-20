# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/rails_mcp/install/install_generator"

# T6 / R7, R8, R9, R11 — the `rails g rails_mcp:install` generator stamps the
# app-owned, fail-closed seams: an `ApplicationMcpTool`, the `RegisteredTools`
# allow-list, an initializer, the `/mcp` route line, one read-only example tool, and
# example tests. These run the real generator into a tmp destination and assert on the
# stamped files, per conventions (real objects, one behavior per test).
#
# Spec 0009 (R2, R3): the allow-list is the app-owned `RegisteredTools.all` array;
# the controller passes `tools: RegisteredTools.all`; the initializer no longer
# registers tools (RailsMcp::Registry / expose! removed).
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

  # spec 0009 R2: the allow-list is stamped as the app-owned RegisteredTools list, not
  # in the initializer. The initializer no longer registers tools, and the example tool
  # is not registered via a removed `expose!` macro.
  def test_registration_is_app_owned_registered_tools_not_initializer_or_expose
    with_routes_file
    run_generator
    assert_file "config/initializers/rails_mcp.rb" do |content|
      refute_match(/RailsMcp\.registry/, content,
        "the initializer must not register tools — the allow-list is RegisteredTools")
      refute_match(/\.register\(/, content,
        "the initializer must not call register — RailsMcp::Registry is removed")
    end
    assert_file "app/mcp/example_read_only_tool.rb" do |content|
      refute_match(/expose!/, content,
        "the generated example tool must not use the removed expose! macro")
    end
  end

  # spec 0009 R2: the generator stamps an app-owned RegisteredTools module whose `.all`
  # returns an explicit array of tool classes seeded with ExampleReadOnlyTool.
  def test_creates_registered_tools_list
    with_routes_file
    run_generator
    assert_file "app/mcp/registered_tools.rb" do |content|
      assert_match(/module RegisteredTools/, content,
        "must stamp an app-owned RegisteredTools module")
      assert_match(/def self\.all/, content,
        "RegisteredTools must expose `.all`")
      assert_match(/ExampleReadOnlyTool/, content,
        "the stamped list must be seeded with ExampleReadOnlyTool")
    end
  end

  # spec 0009 R2: RegisteredTools.all returns an array literal of tool classes (the
  # explicit, editable allow-list), not a registry lookup.
  def test_registered_tools_all_returns_array_of_classes
    with_routes_file
    run_generator
    assert_file "app/mcp/registered_tools.rb" do |content|
      assert_match(/\[\s*\n\s*ExampleReadOnlyTool\s*\n\s*\]/m, content,
        "RegisteredTools.all must return an explicit array of tool classes")
      refute_match(/RailsMcp\.registry/, content,
        "RegisteredTools must not delegate to the removed registry")
    end
  end

  # spec 0009 R2/R3: the stamped RegisteredTools is commented as the one place listing
  # what the AI may call, guiding the app to add a class to expose a tool.
  def test_registered_tools_documents_allow_list_role
    with_routes_file
    run_generator
    assert_file "app/mcp/registered_tools.rb", /allow-list|what the AI may call/i
  end

  # spec 0009 R2: the initializer keeps its audit-subscribe half unchanged.
  def test_initializer_keeps_audit_subscribe
    with_routes_file
    run_generator
    assert_file "config/initializers/rails_mcp.rb",
      /ActiveSupport::Notifications\.subscribe\("invoke\.rails_mcp"\)/
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

  # R1 / spec 0009 R2: the controller builds the server on the `mcp` gem's public
  # per-request pattern — a fresh MCP::Server from the app-owned RegisteredTools.all.
  def test_mcp_controller_builds_server_on_public_mcp_api
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/MCP::Server\.new/, content, "controller must build a fresh MCP::Server")
      assert_match(/tools:\s*RegisteredTools\.all/, content,
        "the server's tool set must be RegisteredTools.all (the app-owned allow-list)")
      refute_match(/RailsMcp\.registry/, content,
        "the controller must not reference the removed RailsMcp.registry")
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

  # R3: the stamped controller frames the acting identity neutrally — it does not
  # describe the resolved user as necessarily a "staff" user or an internal-only
  # audience. The user: keyword itself is unchanged (asserted elsewhere).
  def test_mcp_controller_frames_identity_neutrally
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      refute_match(/staff/i, content,
        "controller must not frame the acting identity as a staff user")
      refute_match(/internal[- ]?(only|staff)/i, content,
        "controller must not frame the audience as internal-only")
      assert_match(/acting user your app resolves|identity your app resolves/i, content,
        "controller must frame identity as the acting user the app resolves")
    end
  end

  # R3: the stamped ApplicationMcpTool frames the acting identity neutrally in its
  # comments — no "staff" user framing, no "which human" phrasing.
  def test_application_mcp_tool_frames_identity_neutrally
    with_routes_file
    run_generator
    assert_file "app/mcp/application_mcp_tool.rb" do |content|
      refute_match(/staff/i, content,
        "base tool must not frame the acting identity as a staff user")
      refute_match(/which human/i, content,
        "base tool must not use the 'which human' framing")
      assert_match(/acting user your app resolves|identity your app resolves/i, content,
        "base tool must frame identity as the acting user the app resolves")
    end
  end

  # R3/R6: neutralizing the identity framing does not change the frozen authorize
  # signature or the hardening lines — the controller still skips forgery protection,
  # passes allowed_hosts, and keeps its raising auth seam.
  def test_neutral_framing_preserves_hardening_and_seams
    with_routes_file
    run_generator
    assert_file "app/controllers/mcp_controller.rb" do |content|
      assert_match(/^\s*skip_forgery_protection\b/, content,
        "hardening line skip_forgery_protection must remain")
      assert_match(/Rails\.application\.config\.hosts\.grep\(String\)/, content,
        "hardening line allowed_hosts grep(String) must remain")
      assert_match(/raise RailsMcp::NotAuthorized/, content,
        "the fail-closed auth seam must remain")
    end
    assert_file "app/mcp/application_mcp_tool.rb",
      /def authorize\(user:, args:, tool:\)/
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

  # === spec 0011 R8 — doc-vs-template drift guards (migrated) ==================
  #
  # These two assertions are the only residue kept from the deleted doc-prose
  # suites (spec 0011, TEST-05/SIMP-04). They are NOT prose-presence checks: each
  # cross-checks that a snippet taught in docs/USAGE.md is byte-present in the
  # rendered install template it documents, so the recipe cannot drift from the
  # stamped code. Formerly getting_started_docs_test.rb:50-56 and
  # neutral_conduit_docs_test.rb:103-109.

  ROOT = File.expand_path("../..", __dir__)
  USAGE = File.read(File.join(ROOT, "docs/USAGE.md"))
  README = File.read(File.join(ROOT, "README.md"))
  CONTROLLER_TT = File.read(
    File.join(ROOT, "lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt")
  )

  # spec 0013 R1 (SEC-01): the bearer resolution taught in USAGE.md matches the stamped
  # controller template — now the secure digest-at-rest form (drift guard, migrated from
  # getting_started_docs_test.rb).
  def test_usage_bearer_resolution_matches_stamped_controller_template
    stamped = "find_by(api_token_digest: Digest::SHA256.hexdigest(token))"
    assert_includes CONTROLLER_TT, stamped,
      "the stamped controller template must resolve via the digest column: #{stamped}"
    assert_includes USAGE, stamped,
      "USAGE.md must resolve the bearer via the same digest lookup #{stamped} the template ships"
  end

  # spec 0013 R1 (SEC-01): the stamped bearer example COMMENT parses the header with the
  # anchored scheme regex, not the global `.remove("Bearer ")` gsub.
  def test_controller_template_bearer_comment_uses_anchored_parse
    assert_includes CONTROLLER_TT, '[/\ABearer (.+)\z/, 1]',
      "the bearer example must parse with the anchored regex [/\\ABearer (.+)\\z/, 1]"
    refute_includes CONTROLLER_TT, '.remove("Bearer ',
      "the bearer example must not strip the scheme with a global .remove(\"Bearer \")"
  end

  # spec 0013 R1 (SEC-01): the stamped bearer example COMMENT resolves via the digest
  # column, never a raw `find_by(api_token: token)` on the raw token.
  def test_controller_template_bearer_comment_uses_digest_lookup
    assert_includes CONTROLLER_TT,
      "find_by(api_token_digest: Digest::SHA256.hexdigest(token))",
      "the bearer example must resolve via the api_token_digest column"
    refute_match(/find_by\(api_token:/, CONTROLLER_TT,
      "the bearer example must not do a raw find_by(api_token: token) on the raw token")
  end

  # spec 0013 R1 (SEC-01): README's getting-started auth snippet teaches the same secure
  # recipe — anchored parse + digest lookup, no `.remove("Bearer ")`, no raw
  # `find_by(api_token: token)`.
  def test_readme_auth_snippet_is_the_secure_recipe
    assert_includes README, '[/\ABearer (.+)\z/, 1]',
      "README must parse the bearer with the anchored regex"
    assert_includes README, "api_token_digest",
      "README must resolve via the api_token_digest column"
    refute_includes README, '.remove("Bearer ',
      "README must not strip the scheme with .remove(\"Bearer \")"
    refute_match(/find_by\(api_token:/, README,
      "README must not do a raw find_by(api_token: token)")
  end

  # spec 0013 R1 (SEC-01): USAGE teaches the digest-at-rest column (api_token_digest, not
  # a raw api_token column) and the anchored parse, with no forbidden forms remaining.
  def test_usage_teaches_digest_at_rest_and_anchored_parse
    assert_includes USAGE, "api_token_digest",
      "USAGE must teach the api_token_digest column"
    assert_includes USAGE, '[/\ABearer (.+)\z/, 1]',
      "USAGE must parse the bearer with the anchored regex"
    refute_includes USAGE, '.remove("Bearer ',
      "USAGE must not strip the scheme with .remove(\"Bearer \")"
    refute_match(/find_by\(api_token:\s/, USAGE,
      "USAGE must not do a raw find_by(api_token: token) on the raw token")
  end

  # spec 0013 R1 (SEC-01): the raw token is treated like a password — the token-generation
  # step tells the operator never to log it.
  def test_usage_labels_raw_token_as_a_password
    assert_match(/treat (it )?like a password.*never log/im, USAGE,
      "USAGE must tell the operator to treat the raw token like a password and never log it")
  end

  # spec 0013 R1 (SEC-01): any plaintext-token demo retained for teaching is labeled
  # "demo only — do not ship". The taught path stores no plaintext token, so no
  # raw-column demo shape may appear UNLABELED in README or USAGE.
  def test_any_plaintext_demo_is_labeled_do_not_ship
    [["USAGE.md", USAGE], ["README.md", README]].each do |name, doc|
      # The plaintext-demo shape is a raw `api_token:` store/compare (not the digest column).
      has_plaintext_demo = doc.match?(/find_by\(api_token:|:api_token,\s|api_token:\s*token/)
      if has_plaintext_demo
        assert_match(/demo only.*do not ship/im, doc,
          "#{name}: any retained plaintext-token demo must be labeled 'demo only — do not ship'")
      else
        refute has_plaintext_demo,
          "#{name}: teaches only the digest-at-rest form — no unlabeled plaintext-token demo"
      end
    end
  end

  # spec 0011 R8: the §1a hardening lines taught in USAGE.md match the stamped
  # controller template (drift guard, migrated from neutral_conduit_docs_test.rb).
  def test_usage_1a_hardening_matches_stamped_controller_template
    ["skip_forgery_protection", "Rails.application.config.hosts.grep(String)"].each do |line|
      assert_includes CONTROLLER_TT, line,
        "the stamped controller template must ship the hardening line #{line}"
      assert_includes USAGE, line,
        "USAGE.md §1a must show the same hardening line #{line} the template ships"
    end
  end
end
