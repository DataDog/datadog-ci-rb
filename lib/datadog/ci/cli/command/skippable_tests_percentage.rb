require_relative "base"
require_relative "../../test_optimisation/skippable_percentage/calculator"

module Datadog
  module CI
    module CLI
      module Command
        class SkippableTestsPercentage < Base
          private

          def build_action
            ::Datadog::CI::TestOptimisation::SkippablePercentage::Calculator.new(
              rspec_cli_options: (options[:"rspec-opts"] || "").split,
              verbose: !options[:verbose].nil?,
              spec_path: options[:"spec-path"] || "spec"
            )
          end

          def command_options(opts)
            opts.on("--rspec-opts=[OPTIONS]", "Command line options to pass to RSpec")
          end
        end
      end
    end
  end
end
