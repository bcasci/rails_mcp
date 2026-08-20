# frozen_string_literal: true

require "test_helper"

# ADR constraint guards — the machine-checkable standing constraints from the ADRs,
# gathered in one file (docs/conventions.md "Tests"; SPEC 0011 R9).
#
# These are source-grep / symbol-absence guards, not behavioral tests: they assert the
# gem SOURCE never grows a construct an ADR forbids. Behavioral proofs of the same
# guarantees (allow-list, no-audit-for-raw-tools) live beside their subject in
# tool_test.rb; these guards catch a resurrected construct even if no behavior changes.
#
# Consolidated here (SPEC 0011 R9):
#   - registry / expose! / ToolNameCollision symbol absence + lib/ grep (ADR-0013)
#   - no `inherited` auto-registration hook (ADR-0007)
#   - no hand-rolled JSON-RPC / transport (ADR-0001)
class AdrConstraintsTest < Minitest::Test
  def lib_ruby_files
    lib = File.expand_path("../lib", __dir__)
    Dir.glob(File.join(lib, "**", "*.rb"))
  end

  def gem_ruby_files
    lib = File.expand_path("../lib/rails_mcp", __dir__)
    entry = File.expand_path("../lib/rails_mcp.rb", __dir__)
    Dir.glob(File.join(lib, "**", "*.rb")) + [entry]
  end

  # --- ADR-0013: no gem-side registry / expose! ---

  # R9 (ADR-0013): no `RailsMcp::Registry`, `RailsMcp.registry`, `ToolNameCollision`,
  # or `expose!` symbol survives in the gem's public surface.
  def test_registry_and_expose_symbols_are_gone
    refute RailsMcp.const_defined?(:Registry),
      "RailsMcp::Registry must be removed (ADR-0013)"
    refute RailsMcp.const_defined?(:ToolNameCollision),
      "RailsMcp::ToolNameCollision must be removed (ADR-0013)"
    refute RailsMcp.respond_to?(:registry),
      "RailsMcp.registry must be removed (ADR-0013)"
    refute RailsMcp::Tool.respond_to?(:expose!),
      "the expose! macro must be removed (ADR-0013)"
  end

  # R9 (ADR-0013): `lib/` carries no registry/`expose!`/`ToolNameCollision` reference —
  # the standing machine-checkable constraint. A resurrected registry.rb defining
  # `Registry` fails this grep, so a separate file-path check is not needed.
  def test_lib_has_no_registry_or_expose_references
    offenders = gem_ruby_files.select do |path|
      File.read(path).match?(/RailsMcp\.registry|RailsMcp::Registry|ToolNameCollision|\bexpose!/)
    end

    assert_empty offenders,
      "no registry/expose! reference may remain in lib/ (R9, ADR-0013); found in: #{offenders.join(", ")}"
  end

  # --- ADR-0007: no auto-discovery via an `inherited` hook ---

  # R9 (ADR-0007): the gem source has no `inherited` hook that adds a tool to a served
  # list automatically — exposure is always the app naming the class in its own list.
  def test_gem_source_has_no_inherited_auto_registration_hook
    lib = File.expand_path("../lib/rails_mcp", __dir__)
    ruby_files = Dir.glob(File.join(lib, "**", "*.rb"))

    offenders = ruby_files.select { |path| File.read(path).match?(/def (self\.)?inherited\b/) }

    assert_empty offenders,
      "no `inherited` hook may auto-register tools (R9, ADR-0007); found in: #{offenders.join(", ")}"
  end

  # --- ADR-0001: protocol delegated to `mcp`, no hand-rolled JSON-RPC / transport ---

  # R9 (ADR-0001): no hand-rolled JSON-RPC or transport class/module in the gem — the
  # protocol layer is delegated to the official `mcp` gem. Moved here from
  # test/test_rails_mcp.rb (SPEC 0011 R9).
  def test_gem_ships_no_hand_rolled_jsonrpc_or_transport
    offenders = lib_ruby_files.select do |path|
      code = File.read(path).each_line.reject { |l| l.strip.start_with?("#") }.join
      code.match?(/\b(class|module)\s+\w*(JsonRpc|JSONRPC|Transport)\b/) ||
        code.match?(/"jsonrpc"|'jsonrpc'/)
    end

    assert_empty offenders,
      "gem must delegate JSON-RPC/transport to `mcp` (ADR-0001), found: #{offenders.inspect}"
  end
end
