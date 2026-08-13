# frozen_string_literal: true

require_relative "lib/rails_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "rails_mcp"
  spec.version = RailsMcp::VERSION
  spec.authors = ["Brandon Casci"]
  spec.email = ["brandon.casci@gmail.com"]

  spec.summary = "Expose selected Rails app actions to an AI client over MCP."
  spec.description = "A Rails gem, on top of the official mcp gem, that exposes a hand-picked " \
    "allow-list of app actions to an AI client over MCP (Model Context Protocol). The gem " \
    "provides the tool DSL and seams; each app owns authorization, audit, and tenant scoping. " \
    "A safer replacement for raw rails console/runner access."
  spec.homepage = "https://github.com/bcasci/rails_mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Protocol plumbing is delegated to the official `mcp` gem (ADR-0001): JSON-RPC,
  # the Rack transport, tool schemas, and annotations all come from it. Pinned so
  # the annotation-emitting behavior (SDK #259) the DSL relies on stays stable.
  spec.add_dependency "mcp", "~> 1.1"

  # Rails supplies ActiveSupport::Notifications (the audit seam, R4) and the
  # generator/engine host.
  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "activesupport", ">= 7.1"

  # Test-group dev deps used downstream: rack-test drives the mounted `/mcp`
  # endpoint (T5/T7), rails hosts the T7 dummy-app integration test.
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rails", ">= 7.1"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
