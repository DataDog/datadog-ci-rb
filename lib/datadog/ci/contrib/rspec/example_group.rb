# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::ExampleGroup
        module ExampleGroup
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          # Instance methods for configuration
          module ClassMethods
            def run(reporter = ::RSpec::Core::NullReporter)
              return super if ::RSpec.configuration.dry_run? && !datadog_configuration[:dry_run_enabled]
              return super unless datadog_configuration[:enabled]

              # skip the context hooks if all descendant example are going to be skipped
              # IMPORTANT: must happen before top_level? check because skipping hooks must happen
              # even if it is a nested context
              metadata[:skip] = true if all_examples_skipped_by_datadog?

              # Start context coverage for this example group (for TIA suite-level coverage).
              # This captures code executed in before(:context)/before(:all) hooks.
              # The context_id uses scoped_id which is a stable identifier for RSpec example groups.
              context_id = datadog_context_id
              start_context_coverage(context_id)

              begin
                # return early because we create Datadog::CI::TestSuite only for top-level example groups
                return super unless top_level?

                suite_name = "#{description} at #{file_path}"
                suite_tags = {
                  CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(metadata[:file_path]),
                  CI::Ext::Test::TAG_SOURCE_START => metadata[:line_number].to_s
                }

                test_suite =
                  test_visibility_component&.start_test_suite(
                    suite_name,
                    tags: suite_tags,
                    service: datadog_configuration[:service_name]
                  )

                success = super

                return success unless test_suite

                test_suite.finish

                success
              ensure
                clear_context_coverage(context_id)
              end
            end

            private

            def all_examples_skipped_by_datadog?
              descendant_filtered_examples.all? do |example|
                !example.datadog_unskippable? && test_optimisation_component&.skippable?(example.datadog_test_id) &&
                  !test_management_component&.attempt_to_fix?(example.datadog_fqn_test_id)
              end
            end

            # Returns a stable context ID for this example group.
            # Uses RSpec's scoped_id which uniquely identifies each example group.
            def datadog_context_id
              metadata[:scoped_id] || "#{metadata[:file_path]}:#{metadata[:line_number]}"
            end

            # Starts context coverage collection for this example group.
            # This captures code executed in before(:context)/before(:all) hooks.
            def start_context_coverage(context_id)
              test_optimisation_component&.on_test_context_started(context_id)
            end

            # Clears context coverage for this example group after it finishes.
            def clear_context_coverage(context_id)
              test_optimisation_component&.clear_context_coverage(context_id)
            end

            def datadog_configuration
              Datadog.configuration.ci[:rspec]
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end

            def test_optimisation_component
              Datadog.send(:components).test_optimisation
            end

            def test_management_component
              Datadog.send(:components).test_management
            end
          end
        end
      end
    end
  end
end
