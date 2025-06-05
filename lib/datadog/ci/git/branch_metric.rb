# frozen_string_literal: true

module Datadog
  module CI
    module Git
      # Represents metrics for a git branch comparison
      # including how far behind/ahead it is from a source branch
      # and the common base commit SHA
      class BranchMetric
        attr_reader :branch_name, :behind, :ahead, :base_sha

        def initialize(branch_name:, behind:, ahead:, base_sha:)
          @branch_name = branch_name
          @behind = behind
          @ahead = ahead
          @base_sha = base_sha
        end

        # Checks if the branch is up to date with the source branch
        def up_to_date?
          @behind == 0 && @ahead == 0
        end

        # Used for comparison when finding the best branch
        # Lower divergence score is better
        def divergence_score
          @ahead
        end
      end
    end
  end
end
