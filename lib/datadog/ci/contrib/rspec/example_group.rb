# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module RSpec
        class ExampleResultsCounter
          def initialize(reporter)
            @reporter = reporter
            @examples_start_count = current_examples_count
            @pending_examples_start_count = current_pending_examples_count
          end

          def all_pending_since_start?
            return false unless reporter_counts_examples?

            examples_since_start_count = current_examples_count - @examples_start_count
            pending_examples_since_start_count = current_pending_examples_count - @pending_examples_start_count

            examples_since_start_count == pending_examples_since_start_count
          end

          private

          attr_reader :reporter

          def reporter_counts_examples?
            return @reporter_counts_examples if defined?(@reporter_counts_examples)

            @reporter_counts_examples = reporter.respond_to?(:examples) && !reporter.examples.nil? &&
              reporter.examples.is_a?(Array) && reporter.respond_to?(:pending_examples) &&
              !reporter.pending_examples.nil? && reporter.pending_examples.is_a?(Array)
          end

          def current_examples_count
            return 0 unless reporter_counts_examples?
            reporter.examples.count
          end

          def current_pending_examples_count
            return 0 unless reporter_counts_examples?
            reporter.pending_examples.count
          end
        end

        # Instrument RSpec::Core::ExampleGroup
        module ExampleGroup
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          # Instance methods for configuration
          module ClassMethods
            def run(reporter = ::RSpec::Core::NullReporter)
              return super unless datadog_configuration[:enabled]
              return super unless top_level?

              suite_name = "#{description} at #{file_path}"
              test_suite = Datadog::CI.start_test_suite(suite_name)

              counter = ExampleResultsCounter.new(reporter)

              success = super
              return success unless test_suite

              if success
                if counter.all_pending_since_start?
                  test_suite.skipped!
                else
                  test_suite.passed!
                end
              else
                test_suite.failed!
              end

              test_suite.finish

              success
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end
          end
        end
      end
    end
  end
end
