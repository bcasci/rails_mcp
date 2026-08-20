# frozen_string_literal: true

require "test_helper"

# Spec 0010 — Packaging, CI & release metadata.
# Guards the built gem's public artifact: its file list is an explicit runtime
# allowlist (R1/R2), its release metadata is complete (R6), its description names
# no removed concern (R5), sig/ is gone (R8), and VERSION has a matching dated
# CHANGELOG section (R4). A regression that re-adds an internal path, drops a
# metadata key, or leaves a bumped VERSION under [Unreleased] fails here.
class PackagingTest < Minitest::Test
  GEMSPEC_PATH = File.expand_path("../rails_mcp.gemspec", __dir__)
  GEMSPEC = Gem::Specification.load(GEMSPEC_PATH)
  ROOT = File.expand_path("..", __dir__)

  # Every internal prefix/path that must never appear in the packaged file list (R1).
  FORBIDDEN_PREFIXES = %w[.claude/ .githooks/ test/ specs/ docs/ .github/ sig/].freeze
  FORBIDDEN_PATHS = %w[
    CLAUDE.md REVIEW.md .tool-versions SECURITY.md CODE_OF_CONDUCT.md
  ].freeze

  # R1: the packaged file list includes the runtime files.
  def test_packaged_files_include_the_runtime_paths
    files = GEMSPEC.files
    %w[lib/rails_mcp.rb README.md CHANGELOG.md LICENSE.txt].each do |f|
      assert_includes files, f, "expected #{f} in the packaged file list"
    end
  end

  # R1/R2/R8: the packaged file list excludes every internal prefix (incl. sig/).
  def test_packaged_files_exclude_every_internal_prefix
    FORBIDDEN_PREFIXES.each do |prefix|
      leaked = GEMSPEC.files.select { |f| f.start_with?(prefix) }
      assert_empty leaked, "packaged file list must not include #{prefix} paths"
    end
  end

  # R1/R2: the packaged file list excludes every internal top-level path.
  def test_packaged_files_exclude_internal_top_level_paths
    FORBIDDEN_PATHS.each do |path|
      refute_includes GEMSPEC.files, path,
        "packaged file list must not include #{path}"
    end
  end

  # R1: spec.files is an explicit allowlist, not a git-ls-files denylist.
  def test_gemspec_builds_spec_files_from_an_explicit_allowlist
    source = File.read(GEMSPEC_PATH)
    refute_match(/git ls-files/, source,
      "spec.files must be an explicit allowlist, never a git ls-files denylist")
    assert_match(/Dir\.glob\(["']lib\/\*\*\/\*["']/, source,
      "spec.files must glob lib/**/* as its allowlist base")
  end

  # R5: the description names identity, not the removed tenant-scoping concern.
  def test_gemspec_description_names_identity_not_tenant_scoping
    assert_includes GEMSPEC.description, "authorization, audit, and identity"
    refute_match(/tenant/, File.read(GEMSPEC_PATH),
      "the string 'tenant' must not appear anywhere in the gemspec")
  end

  # R6: the gemspec sets all required RubyGems metadata keys.
  def test_gemspec_sets_required_metadata_keys
    metadata = GEMSPEC.metadata
    %w[homepage_uri source_code_uri changelog_uri bug_tracker_uri
      rubygems_mfa_required].each do |key|
      assert metadata.key?(key), "expected gemspec metadata to set #{key}"
    end
  end

  # R6: rubygems_mfa_required is the string "true".
  def test_gemspec_requires_rubygems_mfa
    assert_equal "true", GEMSPEC.metadata["rubygems_mfa_required"]
  end

  # R6: bug_tracker_uri points at the homepage issues.
  def test_gemspec_bug_tracker_uri_points_at_homepage_issues
    assert_equal "#{GEMSPEC.homepage}/issues", GEMSPEC.metadata["bug_tracker_uri"]
  end

  # R8: the default RBS stub and its directory are gone from the tree.
  def test_sig_directory_is_removed
    refute File.exist?(File.join(ROOT, "sig", "rails_mcp.rbs")),
      "the default RBS stub sig/rails_mcp.rbs must be deleted"
    refute File.directory?(File.join(ROOT, "sig")),
      "the sig/ directory must be gone"
  end

  # R4: VERSION has a matching dated CHANGELOG section (## [VERSION] - DATE).
  def test_version_has_a_matching_dated_changelog_section
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))
    dated = /^## \[#{Regexp.escape(RailsMcp::VERSION)}\] - \d{4}-\d{2}-\d{2}$/o
    assert_match dated, changelog,
      "expected a dated CHANGELOG section '## [#{RailsMcp::VERSION}] - YYYY-MM-DD'"
  end

  # R4: the current VERSION's changes are not left only under [Unreleased].
  def test_current_version_is_not_only_under_unreleased
    changelog = File.read(File.join(ROOT, "CHANGELOG.md"))
    unreleased = changelog[/^## \[Unreleased\]\n(.*?)(?=^## \[)/m, 1].to_s
    refute_match(/#{Regexp.escape(RailsMcp::VERSION)}/o, unreleased,
      "VERSION #{RailsMcp::VERSION} must not appear only under [Unreleased]")
  end
end
