# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"
require_relative "suite"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Lifecycle hooks to instrument Minitest::Test
        module Hooks
          def before_setup
            super
            return unless datadog_configuration[:enabled]

            test_name = "#{class_name}##{name}"

            test_suite_name = Suite.name(self.class, name)
            if parallel?
              test_suite_name = "#{test_suite_name} (parallel execution of #{test_name})"
            end

            CI.start_test(
              test_name,
              test_suite_name,
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Minitest::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => CI::Ext::Test::TEST_TYPE
              },
              service: datadog_configuration[:service_name]
            )
          end

          def after_teardown
            test_span = CI.active_test
            return super unless test_span

            case result_code
            when "."
              test_span.passed!
            when "E", "F"
              test_suite_name = test_span.test_suite_name
              test_suite = CI.active_test_suite(test_suite_name) if test_suite_name
              test_suite.failed! if test_suite

              test_span.failed!(exception: failure)
            when "S"
              test_span.skipped!(reason: failure.message)
            end

            test_span.finish

            super
          end

          private

          def parallel?
            self.class.test_order == :parallel
          end

          def datadog_configuration
            Datadog.configuration.ci[:minitest]
          end
        end
      end
    end
  end
end
