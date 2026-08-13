# frozen_string_literal: true

module DummyApp
  # A concrete READ-ONLY diagnostic tool the dummy app registers, named for its
  # domain action (docs/conventions.md). It subclasses the app-owned
  # ApplicationMcpTool, so it inherits the real authorize + audit seams. Read-only:
  # it looks up and returns text, mutating nothing (v1, ADR-0003).
  class HouseholdLookupTool < ApplicationMcpTool
    tool_name "household_lookup"
    description "Look up a household by id (read-only)."

    arg :household_id, :integer, required: true, description: "the household to look up"

    read_only!

    def perform(household_id:)
      text_response("household #{household_id} on tenant #{DummyApp::Current.tenant&.id}")
    end
  end
end
