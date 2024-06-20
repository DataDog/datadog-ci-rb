# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestOptimisation
      module SkippablePercentage
        # This class calculates the percentage of tests that are going to be skipped in the next run
        # without actually running the tests.
        #
        # It is useful to determine the number of parallel jobs that are required for the CI pipeline.
        #
        # NOTE: Only RSpec is supported at the moment.
        class Calculator < Base
          def initialize(rspec_cli_options: [], verbose: false, spec_path: "spec")
            super(verbose: verbose, spec_path: spec_path)

            @rspec_cli_options = rspec_cli_options || []
          end

          def call
            return 0.0 if @failed

            require_rspec!
            return 0.0 if @failed

            configure_datadog

            exit_code = dry_run
            if exit_code != 0
              Datadog.logger.error("RSpec dry-run failed with exit code #{exit_code}")
              @failed = true
              return 0.0
            end

            log("Total tests count: #{test_optimisation.total_tests_count}")
            log("Skipped tests count: #{test_optimisation.skipped_tests_count}")
            validate_test_optimisation_state!

            (test_optimisation.skipped_tests_count.to_f / test_optimisation.total_tests_count.to_f).floor(2)
          end

          private

          def require_rspec!
            require "rspec/core"
          rescue LoadError
            Datadog.logger.error("RSpec is not installed, currently this functionality is only supported for RSpec.")
            @failed = true
          end

          def configure_datadog
            Datadog.configure do |c|
              c.ci.enabled = true
              c.ci.itr_enabled = true
              c.ci.retry_failed_tests_enabled = false
              c.ci.retry_new_tests_enabled = false
              c.ci.discard_traces = true
              c.ci.instrument :rspec, dry_run_enabled: true
              c.tracing.enabled = true
            end
          end

          def dry_run
            cli_options_array = @rspec_cli_options + ["--dry-run", @spec_path]

            rspec_config_options = ::RSpec::Core::ConfigurationOptions.new(cli_options_array)
            devnull = File.new("/dev/null", "w")
            out = @verbose ? $stdout : devnull
            err = @verbose ? $stderr : devnull

            ::RSpec::Core::Runner.new(rspec_config_options).run(out, err)
          end
        end
      end
    end
  end
end
