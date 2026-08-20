# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rails_mcp"

# ActiveSupport::Notifications.instrument lazily reaches for
# ActiveSupport::IsolatedExecutionState; require it here so any test file that
# emits an `invoke.rails_mcp` event passes in isolation (TEST-01) without
# depending on another test having autoloaded it first.
require "active_support/isolated_execution_state"

require "minitest/autorun"
