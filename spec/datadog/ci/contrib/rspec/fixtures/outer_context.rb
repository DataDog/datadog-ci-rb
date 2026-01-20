# frozen_string_literal: true

# Helper class for testing context coverage feature with nested contexts.
# Called in OUTER before(:context) hooks to verify that code coverage
# from outer contexts is properly propagated to tests in sibling nested contexts.

module ContextCoverageHelper
  class OuterContext
    def self.setup
      "outer context setup called"
    end
  end
end
