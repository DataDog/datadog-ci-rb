# frozen_string_literal: true

# Helper class for testing context coverage feature.
# Called in before(:context) hooks to verify that code coverage
# is properly collected during context setup.

module ContextCoverageHelper
  class User
    attr_reader :first_name, :last_name

    def initialize(first_name, last_name)
      @first_name = first_name
      @last_name = last_name
    end

    def full_name
      "#{first_name} #{last_name}"
    end
  end
end
