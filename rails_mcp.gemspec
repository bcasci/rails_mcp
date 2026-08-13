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

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
