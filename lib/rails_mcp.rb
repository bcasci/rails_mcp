# frozen_string_literal: true

require_relative "rails_mcp/version"
require_relative "rails_mcp/errors"

# `rails_mcp` — a thin conventions-and-seams layer over the official `mcp` gem
# that exposes a hand-picked allow-list of Rails app actions to an AI client
# over MCP. The gem ships the tool DSL and two seams (`authorize` and the
# `invoke.rails_mcp` notification); each app owns authorization, audit, and
# identity (ADR-0004). Protocol plumbing — JSON-RPC, the Rack
# transport, tool schemas, and annotations — is delegated to `mcp` (ADR-0001).
#
# The exception hierarchy (`Error` and its subclasses) lives in
# `rails_mcp/errors` and is required first (ARCH-04).

# Submodule wiring. Each later task owns its own file under lib/rails_mcp/ and is
# loaded from here; T0 stamps these lines up front so no later task edits this
# entry file (disjoint file ownership is what lets the build run in parallel).
# A line loads once its owning task has landed its file — the gem loads cleanly
# at every stage of the build, and ships with all of them present.
%w[
  rails_mcp/args
  rails_mcp/annotations
  rails_mcp/instrumentation
  rails_mcp/tool
].each do |submodule|
  path = File.expand_path("#{submodule}.rb", __dir__)
  require_relative submodule if File.exist?(path)
end
