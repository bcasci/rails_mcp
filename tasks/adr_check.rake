# frozen_string_literal: true

# adr:check — the single shared constraint gate (SEC-04, SEC-05).
#
# One task, run by BOTH `.githooks/pre-commit` AND the `default` rake task (so
# `bundle exec rake`, as CI runs, runs it too). It replaces the pre-commit hook's
# inline grep block: the hook and CI now run the identical check, and there is no
# grep duplicated between them.
#
# The checks are the standing machine-checkable ADR constraints:
#   - no debugger (`binding.pry`/`binding.irb`) left in gem code (ADR-0004)
#   - no arbitrary-Ruby eval-family (ADR-0004: allow-list only, no console)
#   - no extended dynamic dispatch that turns an AI-supplied string into a class or
#     method — `constantize`, `const_get`, `public_send`, bareword `.send(` (SEC-05)
#   - no credential (token/secret/bearer/password/api_key) logged or stored raw in
#     gem or stamped code (SEC-04, "Generated example security")
#   - no gem-side policy/tenant/shard machinery (ADR-0004: gem owns zero policy)
#
# Each check is a named regex applied to the code lines (comments stripped) of a set
# of paths. A match prints the offending file:line and fails the task. The check is
# defined as plain Ruby (RailsMcp::AdrCheck) so a test can drive it against fixtures.

require_relative "adr_check_lib"

namespace :adr do
  desc "Run the ADR / credential / dynamic-dispatch constraint greps (SEC-04, SEC-05)."
  task :check do
    root = File.expand_path("..", __dir__)
    violations = RailsMcp::AdrCheck.run(root: root)

    unless violations.empty?
      warn "[adr:check] BLOCKED — constraint violations:"
      violations.each do |v|
        warn "  #{v[:check]}: #{v[:file]}:#{v[:line]}: #{v[:text].strip}"
      end
      abort "[adr:check] #{violations.length} violation(s). See docs/adr/ and docs/conventions.md."
    end

    puts "[adr:check] clean"
  end
end
