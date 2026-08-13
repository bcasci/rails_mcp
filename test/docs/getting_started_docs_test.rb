# frozen_string_literal: true

require "test_helper"

# Doc-content tests for spec 0007 "Getting started" — the "Make your first call"
# recipe in docs/USAGE.md and its condensed form in README.md. Pure string
# assertions over the shipped docs, one acceptance criterion per test. The tool
# name and route asserted here are cross-checked against the shipped generator
# templates so the recipe can never drift from the code it documents.
class GettingStartedDocsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  USAGE = File.read(File.join(ROOT, "docs/USAGE.md"))
  README = File.read(File.join(ROOT, "README.md"))
  CONTROLLER_TT = File.read(
    File.join(ROOT, "lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt")
  )
  TOOL_TT = File.read(
    File.join(ROOT, "lib/generators/rails_mcp/install/templates/example_read_only_tool.rb.tt")
  )
  ROUTE_TT = File.read(
    File.join(ROOT, "lib/generators/rails_mcp/install/templates/routes_mount.rb.tt")
  )

  # === R1 — Token setup matching the shipped bearer example ==================

  # R1: USAGE shows the api_token column migration the stamped bearer path needs.
  def test_usage_shows_api_token_migration
    assert_match(/add_column\s+:users,\s+:api_token/, USAGE,
      "USAGE.md must show an api_token column migration for the bearer path")
  end

  # R1: USAGE seeds the staff user's token with SecureRandom.hex(24).
  def test_usage_seeds_token_with_secure_random_hex_24
    assert_includes USAGE, "SecureRandom.hex(24)",
      "USAGE.md must seed the api_token with SecureRandom.hex(24)"
  end

  # R1: USAGE defines the `staff` scope the stamped example calls (User.staff).
  def test_usage_defines_staff_scope
    assert_match(/scope\s+:staff/, USAGE,
      "USAGE.md must define the `staff` scope used by User.staff.find_by")
  end

  # R1: the recipe's bearer resolution matches the stamped template exactly
  # (User.staff.find_by(api_token: token)).
  def test_usage_bearer_resolution_matches_stamped_template
    stamped = "User.staff.find_by(api_token: token)"
    assert_includes CONTROLLER_TT, stamped,
      "guard: the stamped controller template must resolve via #{stamped}"
    assert_includes USAGE, stamped,
      "USAGE.md must resolve the bearer via the same #{stamped} the template ships"
  end

  # R1: the recipe states ApplicationMcpTool#authorize must be overridden to
  # permit the staff user (the gem default denies), or the first call is blocked.
  def test_usage_states_authorize_must_be_overridden_to_permit_staff
    assert_match(/authorize/, USAGE)
    assert_match(/ApplicationMcpTool/, USAGE)
    assert_match(/first call/i, USAGE,
      "USAGE.md must warn that authorize must permit staff or the first call is denied")
  end

  # === R2 — Runnable JSON-RPC handshake =====================================

  # R2: USAGE gives a pasteable curl initialize POST against /mcp with a bearer.
  def test_usage_curl_initialize_against_mcp_with_bearer
    assert_match(/curl/, USAGE)
    assert_match(/"method":\s*"initialize"/, USAGE,
      "USAGE.md must show an initialize JSON-RPC request")
    assert_match(%r{Authorization:\s*Bearer}, USAGE,
      "USAGE.md curl must send Authorization: Bearer")
    assert_match(%r{/mcp}, USAGE, "USAGE.md curl must target the /mcp route")
  end

  # R2: USAGE shows a tools/list request that surfaces example_read_only.
  def test_usage_curl_tools_list_shows_example_read_only
    assert_match(/"method":\s*"tools\/list"/, USAGE,
      "USAGE.md must show a tools/list request")
    assert_includes USAGE, "example_read_only",
      "USAGE.md tools/list section must show the shipped example_read_only tool"
  end

  # R2: USAGE shows a tools/call of example_read_only ending in a real result.
  def test_usage_curl_tools_call_example_read_only
    assert_match(/"method":\s*"tools\/call"/, USAGE,
      "USAGE.md must show a tools/call request")
    assert_match(/"name":\s*"example_read_only"/, USAGE,
      "USAGE.md tools/call must invoke example_read_only")
  end

  # R2 guard: the recipe's tool name matches the shipped template.
  def test_recipe_tool_name_matches_shipped_template
    assert_includes TOOL_TT, 'tool_name "example_read_only"',
      "guard: shipped template must name the tool example_read_only"
    assert_includes USAGE, "example_read_only"
    assert_includes README, "example_read_only"
  end

  # R2 guard: the recipe's route matches the shipped routes template
  # (POST /mcp -> mcp#handle).
  def test_recipe_route_matches_shipped_template
    assert_includes ROUTE_TT, '"/mcp"'
    assert_includes ROUTE_TT, 'to: "mcp#handle"'
    assert_match(%r{/mcp}, USAGE)
    assert_match(%r{/mcp}, README)
  end

  # R2: README carries the condensed recipe — Gemfile git line, the install
  # generator, wiring auth, and a curl tools/call.
  def test_readme_carries_condensed_recipe
    assert_match(/gem\s+"rails_mcp".*git:/, README,
      "README.md must show the Gemfile git line")
    assert_match(/rails g rails_mcp:install/, README,
      "README.md must show the install generator")
    assert_match(/authenticate_acting_user!/, README,
      "README.md must reference wiring authenticate_acting_user!")
    assert_match(/curl/, README, "README.md must show a curl call")
    assert_match(/tools\/call/, README,
      "README.md must show a curl tools/call")
  end
end
