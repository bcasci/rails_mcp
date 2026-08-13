# frozen_string_literal: true

require "test_helper"

# T2 (spec 0008) — de-opinion the doc surface. README.md, docs/USAGE.md,
# docs/SEAMS.md, docs/conventions.md must carry no read-only/mutation MANDATE
# and no "staff/internal" identity FRAMING; the acting identity is described
# neutrally (R1, R3). USAGE §1a matches the hardened stamped controller (R4);
# the curl recipe states the Accept header and initialize-first fallback (R5).
#
# Pure string assertions over the shipped docs, one acceptance criterion per
# test. Advisory `read_only!` mentions and a read-only *example* are allowed;
# a mandate is not.
class NeutralConduitDocsTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  README = File.read(File.join(ROOT, "README.md"))
  USAGE = File.read(File.join(ROOT, "docs/USAGE.md"))
  SEAMS = File.read(File.join(ROOT, "docs/SEAMS.md"))
  CONVENTIONS = File.read(File.join(ROOT, "docs/conventions.md"))
  DOCS = {"README.md" => README, "USAGE.md" => USAGE, "SEAMS.md" => SEAMS,
          "conventions.md" => CONVENTIONS}

  # The read-only/mutation MANDATE phrasings the spec bans (R1). Advisory
  # `read_only!` and the "read-only diagnostic" example wording are NOT here.
  MANDATE_PATTERNS = [
    /read-only v1/i,
    /v1 is read-only/i,
    /no tool may mutate/i,
    /must not mutate/i,
    /read only in v1/i,
    /no writes\b/i
  ].freeze

  # === R1 — no read-only / mutation mandate on the shipped doc surface =======

  def test_no_mandate_phrasing_in_any_shipped_doc
    DOCS.each do |name, body|
      MANDATE_PATTERNS.each do |pat|
        refute_match pat, body,
          "#{name} must carry no read-only/mutation mandate (matched #{pat.inspect})"
      end
    end
  end

  # R1: README no longer opens by declaring the gem read-only.
  def test_readme_does_not_declare_the_gem_read_only
    refute_match(/v1 is read-only/i, README)
    refute_match(/it can register and invoke read-only diagnostic tools only/i, README)
  end

  # R1: the gem is framed as exposing app-defined tools, read OR write.
  def test_readme_frames_gem_as_neutral_conduit
    assert_match(/read or write|read and\/or write|read.{0,10}write/i, README,
      "README must state the app exposes read or write tools")
  end

  # === R3 — neutral identity framing (no "staff/internal" audience prose) ====

  # R3: no prose calls the acting identity a "staff user" or an internal-only
  # audience. (The worked bearer recipe's own code — User.staff.find_by — is a
  # concrete implementor choice cross-checked against the template, not framing.)
  def test_no_acting_staff_user_framing_prose
    [["README.md", README], ["USAGE.md", USAGE], ["SEAMS.md", SEAMS]].each do |name, body|
      refute_match(/acting staff (?:`?User`?|user)/i, body,
        "#{name} must frame the acting identity neutrally, not as a staff user")
      refute_match(/internal staff-only/i, body,
        "#{name} must not frame the audience as internal staff-only")
      refute_match(/which human/i, body,
        "#{name} must not frame identity as 'which human'")
    end
  end

  # R3: USAGE describes the identity neutrally — "the identity your app resolves"
  # or "the acting user".
  def test_usage_describes_identity_neutrally
    assert_match(/identity your app resolves|acting user/i, USAGE,
      "USAGE must describe the acting identity neutrally")
  end

  # R3: SEAMS' user: keyword and authorize signature are unchanged (guard R3).
  def test_seams_keeps_user_keyword_and_authorize_signature
    assert_match(/def authorize\(user:, args:, tool:\)/, SEAMS,
      "SEAMS must keep the frozen authorize(user:, args:, tool:) signature")
  end

  # === R4 — USAGE §1a matches the hardened stamped controller ================

  # R4: the §1a controller example carries skip_forgery_protection.
  def test_usage_1a_shows_skip_forgery_protection
    assert_includes USAGE, "skip_forgery_protection",
      "USAGE §1a controller example must include skip_forgery_protection"
  end

  # R4: the §1a controller example carries the allowed_hosts host-guard line.
  def test_usage_1a_shows_allowed_hosts_host_guard
    assert_includes USAGE, "Rails.application.config.hosts.grep(String)",
      "USAGE §1a must show allowed_hosts: Rails.application.config.hosts.grep(String)"
  end

  # R4 guard: the hardening lines USAGE §1a shows are the ones the template ships.
  def test_usage_1a_hardening_matches_shipped_template
    controller_tt = File.read(
      File.join(ROOT, "lib/generators/rails_mcp/install/templates/mcp_controller.rb.tt")
    )
    assert_includes controller_tt, "skip_forgery_protection"
    assert_includes controller_tt, "Rails.application.config.hosts.grep(String)"
  end

  # === R5 — curl recipe reality ==============================================

  # R5: the recipe states the Accept header includes both JSON and the SSE stream.
  def test_recipe_states_accept_json_and_event_stream
    assert_match(%r{Accept:\s*application/json,\s*text/event-stream}, USAGE,
      "USAGE curl recipe must send Accept: application/json, text/event-stream")
  end

  # R5: the recipe states the initialize-first fallback when a bare tools/call
  # returns a "not initialized" error.
  def test_recipe_states_initialize_first_on_not_initialized
    assert_match(/not initialized/i, USAGE,
      "USAGE must mention the 'not initialized' error")
    assert_match(/initialize/i, USAGE,
      "USAGE must instruct sending initialize first")
  end
end
