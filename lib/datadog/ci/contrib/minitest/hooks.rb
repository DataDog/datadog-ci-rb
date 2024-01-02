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
              test_suite_name = "#{test_suite_name} (#{name} concurrently)"

              # for parallel execution we need to start a new test suite for each test
              CI.start_test_suite(test_suite_name)
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

            finish_test(test_span, result_code)
            if parallel?
              finish_test_suite(test_span.test_suite, result_code)
            end

            super
          end

          private

          def finish_test(test_span, result_code)
            finish_with_result(test_span, result_code)

            # mark test suite as failed if any test failed
            if test_span.failed?
              test_suite = test_span.test_suite
              test_suite.failed! if test_suite
            end
          end

          def finish_test_suite(test_suite, result_code)
            return unless test_suite

            finish_with_result(test_suite, result_code)
          end

          def finish_with_result(span, result_code)
            case result_code
            when "."
              span.passed!
            when "E", "F"
              span.failed!(exception: failure)
            when "S"
              span.skipped!(reason: failure.message)
            end
            span.finish
          end

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
