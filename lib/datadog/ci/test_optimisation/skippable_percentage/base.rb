# frozen_string_literal: true

module Datadog
  module CI
    module TestOptimisation
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

          def validate_test_optimisation_state!
            unless test_optimisation.enabled
              error!("ITR wasn't enabled, check the environment variables (DD_SERVICE, DD_ENV)")
            end

            if test_optimisation.skippable_tests_fetch_error
              error!("Skippable tests couldn't be fetched, error: #{test_optimisation.skippable_tests_fetch_error}")
            end
          end

          def log(message)
            Datadog.logger.info(message) if @verbose
          end

          def error!(message)
            Datadog.logger.error(message)
            @failed = true
          end

          def test_optimisation
            Datadog.send(:components).test_optimisation
          end

          def test_visibility
            Datadog.send(:components).test_visibility
          end
        end
      end
    end
  end
end
