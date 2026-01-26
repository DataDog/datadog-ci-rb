# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      module SkippablePercentage
        class Base
          attr_reader :failed

          def initialize(verbose: false, spec_path: "spec")
            @verbose = verbose
            @spec_path = spec_path
            @failed = false

            log("Spec path: #{@spec_path}")
            error!("Spec path is not a directory: #{@spec_path}") if !File.directory?(@spec_path)
          end

          def call
            0.0
          end

          private

          def validate_test_impact_analysis_state!
            unless test_impact_analysis.enabled
              error!("ITR wasn't enabled, check the environment variables (DD_SERVICE, DD_ENV)")
            end

            if test_impact_analysis.skippable_tests_fetch_error
              error!("Skippable tests couldn't be fetched, error: #{test_impact_analysis.skippable_tests_fetch_error}")
            end
          end

          def log(message)
            Datadog.logger.info(message) if @verbose
          end

          def error!(message)
            Datadog.logger.error(message)
            @failed = true
          end

          def test_impact_analysis
            Datadog.send(:components).test_impact_analysis
          end

def test_tracing
          Datadog.send(:components).test_tracing
        end
        end
      end
    end
  end
end
