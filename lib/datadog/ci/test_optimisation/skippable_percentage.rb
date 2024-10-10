# frozen_string_literal: true

module Datadog
  module CI
    module TestOptimisation
      # This class claculates the percentage of tests that are going to be skipped in the next run
      # without actually running the tests.
      #
      # It is useful to determine the number of parallel jobs that are required for the CI pipeline.
      #
      # NOTE: Only RSpec is supported at the moment.
      class SkippablePercentage
        def initialize(rspec_cli_options: [])
          @rspec_cli_options = rspec_cli_options || []
        end

        def calculate
          begin
            require "rspec/core"
          rescue LoadError
            Datadog.logger.error("RSpec is not installed. Please add it to your Gemfile.")
            Kernel.exit(1)
          end

          require "datadog/ci"

          Datadog.configure do |c|
            c.ci.enabled = true
            c.ci.itr_enabled = true
            c.ci.discard_traces = true
            c.ci.instrument :rspec, dry_run_enabled: true
            c.tracing.enabled = true
          end

          cli_options_array = @rspec_cli_options + %w[
            --dry-run
            spec
          ]

          rspec_config_options = ::RSpec::Core::ConfigurationOptions.new(cli_options_array)
          devnull = File.new("/dev/null", "w")
          exit_code = ::RSpec::Core::Runner.new(rspec_config_options).run(devnull, devnull)

          if exit_code != 0
            Datadog.logger.error("RSpec dry-run failed with exit code #{exit_code}")
          end

          test_optimisation = Datadog.send(:components).test_optimisation

          (test_optimisation.skipped_tests_count.to_f / test_optimisation.total_tests_count).floor(2)
        end
      end
    end
  end
end
