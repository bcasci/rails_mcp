# frozen_string_literal: true

require "test_helper"

# T2 (spec 0007) — Client-auth reality note in docs/SEAMS.md (R3) and the
# CHANGELOG `[Unreleased]` entry (R4). Docs-only; the recipe documents existing
# seams and adds no gem runtime change (R5).
#
# These tests assert on the shipped doc content, matching the repo's doc-content
# test pattern (test_rails_mcp.rb reads a file and asserts on its text).
class GettingStartedSeamsDocsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SEAMS = File.read(File.join(ROOT, "docs", "SEAMS.md"))
  CHANGELOG = File.read(File.join(ROOT, "CHANGELOG.md"))

  # --- R3: client-auth reality note, stated once ------------------------------

  # R3: v1 is a static `Authorization: Bearer` over Streamable HTTP.
  def test_seams_states_v1_is_static_bearer_over_streamable_http
    assert_match(/static\s+`?Authorization: Bearer`?/, SEAMS)
    assert_match(/Streamable HTTP/, SEAMS)
  end

  # R3: validate with curl or an MCP inspector that accepts a custom header.
  def test_seams_says_validate_with_curl_or_an_inspector_that_accepts_a_custom_header
    assert_match(/curl/, SEAMS)
    assert_match(/inspector/i, SEAMS)
    assert_match(/custom header/i, SEAMS)
  end

  # R3: Claude's hosted remote-MCP connector expects OAuth 2.1, so a static
  # Bearer from that surface is not guaranteed (do not promise it).
  def test_seams_notes_hosted_connector_expects_oauth_and_static_bearer_is_not_guaranteed
    assert_match(/OAuth 2\.1/, SEAMS)
    assert_match(/not guaranteed/i, SEAMS)
  end

  # R3: the client-auth reality is stated once — a single note, not repeated.
  def test_seams_states_the_client_auth_reality_exactly_once
    assert_equal 1, SEAMS.scan("OAuth 2.1").length,
      "the static-Bearer-vs-OAuth reality must be stated once"
  end

  # --- R4: CHANGELOG [Unreleased] entry ---------------------------------------

  def test_changelog_has_an_unreleased_section
    assert_match(/^##\s*\[Unreleased\]/, CHANGELOG)
  end

  # R4: [Unreleased] records the tenancy strip (spec 0006).
  def test_changelog_unreleased_records_the_tenancy_strip
    assert_match(/tenanc/i, unreleased_section)
  end

  # R4: [Unreleased] records the dummy_app removal.
  def test_changelog_unreleased_records_the_dummy_app_removal
    assert_match(/dummy_app/, unreleased_section)
  end

  # R4: [Unreleased] records the doc seam/route corrections.
  def test_changelog_unreleased_records_the_doc_seam_route_corrections
    assert_match(/seam/i, unreleased_section)
    assert_match(/route/i, unreleased_section)
  end

  # R4: [Unreleased] records the Getting-started recipe.
  def test_changelog_unreleased_records_the_getting_started_recipe
    assert_match(/getting[- ]started/i, unreleased_section)
  end

  # --- R5: no gem runtime change (docs/CHANGELOG only) -------------------------

  # R5: this spec's owned files are docs/CHANGELOG; nothing under lib/ carries a
  # 0007 marker. Guards that the note stayed in docs, not gem runtime.
  def test_no_lib_file_references_this_docs_only_recipe
    lib_dir = File.join(ROOT, "lib")
    offenders = Dir.glob(File.join(lib_dir, "**", "*.rb")).select do |path|
      File.read(path).match?(/getting[- ]started/i)
    end
    assert_empty offenders,
      "the getting-started recipe is docs-only (R5); found lib refs: #{offenders.inspect}"
  end

  private

  # The text between `## [Unreleased]` and the next `## [` heading.
  def unreleased_section
    CHANGELOG[/^##\s*\[Unreleased\].*?(?=^##\s*\[)/m] || ""
  end
end
