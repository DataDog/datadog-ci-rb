require_relative "base"
require_relative "../../test_optimisation/skippable_percentage/estimator"

module Datadog
  module CI
    module CLI
      module Command
        class SkippableTestsPercentageEstimate < Base
          private

          def build_action
            ::Datadog::CI::TestOptimisation::SkippablePercentage::Estimator.new(
              verbose: !options[:verbose].nil?,
              spec_path: options[:"spec-path"] || "spec"
            )
          end
        end
      end
    end
  end
end
