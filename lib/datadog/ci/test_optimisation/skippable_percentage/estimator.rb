# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestOptimisation
      module SkippablePercentage
        # This class estimates the percentage of tests that are going to be skipped in the next run
        # without actually running the tests. This estimate is very rough:
        #
        # - it counts the number of lines that start with "it" or "scenario" in the spec files, which could be inaccurate
        #   if you use shared examples
        # - it only counts the number of tests that could be skipped, this does not mean that they will be actually skipped:
        #   if in this commit you replaced all the tests in your test suite with new ones, all the tests would be run (but
        #   this is highly unlikely)
        #
        # It is useful to determine the number of parallel jobs that are required for the CI pipeline.
        #
        # NOTE: Only RSpec is supported at the moment.
        class Estimator < Base
          def initialize(verbose: false, spec_path: "spec")
            super
          end

          def call
            return 0.0 if @failed

            Datadog.configure do |c|
              c.ci.enabled = true
              c.ci.itr_enabled = true
              c.ci.retry_failed_tests_enabled = false
              c.ci.retry_new_tests_enabled = false
              c.ci.discard_traces = true
              c.tracing.enabled = true
            end

            spec_files = Dir["#{@spec_path}/**/*_spec.rb"]
            estimated_tests_count = spec_files.sum do |file|
              content = File.read(file)
              content.scan(/(^\s*it\s+)|(^\s*scenario\s+)/).size
            end

            # starting and finishing a test session is required to get the skippable tests response
            Datadog::CI.start_test_session(total_tests_count: estimated_tests_count)&.finish
            skippable_tests_count = test_optimisation.skippable_tests_count

            log("Estimated tests count: #{estimated_tests_count}")
            log("Skippable tests count: #{skippable_tests_count}")
            validate_test_optimisation_state!

            [(skippable_tests_count.to_f / estimated_tests_count).floor(2), 0.99].min || 0.0
          end
        end
      end
    end
  end
end
