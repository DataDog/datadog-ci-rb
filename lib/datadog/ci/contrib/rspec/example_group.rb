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
              return super unless top_level?

              suite_name = "#{description} at #{file_path}"
              test_suite = test_visibility_component.start_test_suite(
                suite_name,
                tags: {
                  CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(metadata[:file_path]),
                  CI::Ext::Test::TAG_SOURCE_START => metadata[:line_number].to_s
                }
              )

              success = super
              return success unless test_suite

              if success && test_suite.any_passed?
                test_suite.passed!
              elsif success
                test_suite.skipped!
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

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end
          end
        end
      end
    end
  end
end
