# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

# The shared ADR / credential / dynamic-dispatch constraint gate (SEC-04). Loaded
# here so `bundle exec rake` (as CI runs) runs `adr:check` as part of the default
# task, and `.githooks/pre-commit` runs the identical `rake adr:check`.
load File.expand_path("tasks/adr_check.rake", __dir__)

task default: %i[test standard adr:check]
