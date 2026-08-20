# frozen_string_literal: true

require "test_helper"

# T0 — Gem skeleton, gemspec, dependency on official `mcp` (R12).
# Acceptance: the gem loads and exposes its namespace, the gemspec pins the
# official `mcp` gem, declares the downstream test-group dev deps, and the gem
# ships no hand-rolled JSON-RPC / transport (protocol delegated to `mcp`).
class TestRailsMcp < Minitest::Test
  GEMSPEC = Gem::Specification.load(File.expand_path("../rails_mcp.gemspec", __dir__))

  # R12: `require "rails_mcp"` loads without error and exposes the namespace.
  def test_requiring_the_gem_exposes_the_rails_mcp_namespace
    assert_kind_of Module, ::RailsMcp
  end

  def test_that_it_has_a_version_number
    refute_nil ::RailsMcp::VERSION
  end

  # R12: the official `mcp` gem is a declared, pinned runtime dependency.
  def test_gemspec_pins_the_official_mcp_gem_as_a_runtime_dependency
    dep = GEMSPEC.dependencies.find { |d| d.name == "mcp" && d.type == :runtime }
    refute_nil dep, "expected a runtime dependency on the official `mcp` gem"
    assert dep.requirement != Gem::Requirement.default,
      "expected the `mcp` dependency to be pinned to a version, not unbounded"
  end

  # R12/T0: gemspec declares the downstream test-group dev deps: rack-test and rails.
  def test_gemspec_declares_rack_test_dev_dependency
    dep = GEMSPEC.dependencies.find { |d| d.name == "rack-test" && d.type == :development }
    refute_nil dep, "expected a development dependency on `rack-test`"
  end

  def test_gemspec_declares_rails_dev_dependency
    dep = GEMSPEC.dependencies.find { |d| d.name == "rails" && d.type == :development }
    refute_nil dep, "expected a development dependency on `rails`"
  end

  # NOTE: the no-hand-rolled-JSON-RPC/transport grep (ADR-0001) moved to
  # test/adr_constraints_test.rb, where the ADR source-grep guards live together
  # (SPEC 0011 R9).
end
