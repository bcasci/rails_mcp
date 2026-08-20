# frozen_string_literal: true

require "test_helper"

# ADR-integrity guard (SPEC 0012 R2, DOC-02).
#
# An Accepted ADR is a live decision. If an Accepted, non-superseded ADR still names a
# symbol the codebase removed (`RailsMcp::Registry`, `RailsMcp.registry`, `expose!`,
# `ToolNameCollision` — the symbols `test/adr_constraints_test.rb` proves gone), the docs
# and the shipped code have silently diverged. This scans every `docs/adr/*.md` and asserts
# no such divergence.
#
# Exempt (an Accepted ADR that names a removed symbol legitimately):
#   - `_template.md` — the scaffold, not a decision.
#   - a Superseded / partially-superseded ADR — its decision no longer stands (0007/0008/0009).
#   - an ADR whose body carries a `Supersedes:` line — the ADR that performed the removal
#     necessarily names the symbol it removed (ADR-0013).
class AdrIntegrityTest < Minitest::Test
  REMOVED_SYMBOLS = [
    "RailsMcp::Registry",
    "RailsMcp.registry",
    "expose!",
    "ToolNameCollision"
  ].freeze

  def adr_dir
    File.expand_path("../../docs/adr", __dir__)
  end

  def adr_files
    Dir.glob(File.join(adr_dir, "*.md")).reject { |p| File.basename(p) == "_template.md" }
  end

  def status_line(body)
    body.each_line.find { |l| l.start_with?("Status:") }.to_s
  end

  # An ADR is a "live decision" (subject to the removed-symbol check) when its Status says
  # Accepted, it is not (partially) superseded, and its body carries no `Supersedes:` line.
  def live_decision?(body)
    status = status_line(body)
    return false unless status.match?(/accepted/i)
    return false if status.match?(/superseded/i)
    return false if body.match?(/^Supersedes:/i)

    true
  end

  def removed_symbols_in(body)
    REMOVED_SYMBOLS.select { |sym| body.include?(sym) }
  end

  # R2: no Accepted, non-superseded ADR (without a `Supersedes:` line) names a removed
  # symbol. A future Accepted ADR that reintroduces a live registry reference fails here.
  def test_no_live_accepted_adr_names_a_removed_symbol
    offenders = adr_files.filter_map do |path|
      body = File.read(path)
      next unless live_decision?(body)

      found = removed_symbols_in(body)
      next if found.empty?

      "#{File.basename(path)} names #{found.join(", ")}"
    end

    assert_empty offenders,
      "Accepted, non-superseded ADRs must not name removed symbols (R2, DOC-02): #{offenders.join("; ")}"
  end

  # R2: ADR-0013 (the ADR that removed the registry) is present, Accepted, names the removed
  # symbols, and is NOT flagged — its `Supersedes:` line exempts it. This exercises the
  # exemption rather than merely asserting it, so the check does not false-positive on the
  # removal ADR.
  def test_removal_adr_is_present_accepted_names_symbols_and_is_exempt
    path = File.join(adr_dir, "0013-drop-registry-for-app-owned-tool-list.md")
    assert File.exist?(path), "ADR-0013 must exist"
    body = File.read(path)

    assert status_line(body).match?(/accepted/i), "ADR-0013 must be Accepted"
    refute status_line(body).match?(/superseded/i), "ADR-0013 must not be superseded"
    assert body.match?(/^Supersedes:/i), "ADR-0013 must carry a Supersedes: line"
    refute_empty removed_symbols_in(body),
      "ADR-0013 must name the removed symbols it removed (exemption must be exercised)"
    refute live_decision?(body),
      "ADR-0013's Supersedes: line must exempt it from the removed-symbol check"
  end

  # R2: ADR-0007 and ADR-0008 are re-statused as partially superseded by ADR-0013, with a
  # link — so they are exempt and their retained registry/`expose!` references do not fail.
  def test_partially_superseded_adrs_are_relinked_and_exempt
    %w[0007-convenience-without-lock-in 0008-controller-uses-mcp-public-pattern].each do |slug|
      body = File.read(File.join(adr_dir, "#{slug}.md"))
      status = status_line(body)

      assert status.match?(/partially superseded by \[ADR-0013\]/i),
        "#{slug} Status must be partially superseded by [ADR-0013]"
      refute live_decision?(body),
        "#{slug} must be exempt from the removed-symbol check once re-statused"
    end
  end

  # R2: ADR-0013 links back to ADR-0007 and ADR-0008 (bidirectional link, per CLAUDE.md).
  def test_removal_adr_links_back_to_partially_superseded_adrs
    body = File.read(File.join(adr_dir, "0013-drop-registry-for-app-owned-tool-list.md"))

    assert_match(/\[ADR-0007\]\(0007-convenience-without-lock-in\.md\)/, body,
      "ADR-0013 must link back to ADR-0007")
    assert_match(/\[ADR-0008\]\(0008-controller-uses-mcp-public-pattern\.md\)/, body,
      "ADR-0013 must link back to ADR-0008")
  end
end
