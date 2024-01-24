# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"
require_relative "helpers"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Lifecycle hooks to instrument Minitest::Test
        module Hooks
          def before_setup
            super
            return unless datadog_configuration[:enabled]

            test_suite_name = Helpers.test_suite_name(self.class, name)
            if Helpers.parallel?(self.class)
              test_suite_name = "#{test_suite_name} (#{name} concurrently)"

              # for parallel execution we need to start a new test suite for each test
              CI.start_test_suite(test_suite_name)
            end

            source_file, line_number = method(name).source_location

            CI.start_test(
              name,
              test_suite_name,
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Minitest::Integration.version.to_s,
                CI::Ext::Test::TAG_SOURCE_FILE => Utils::Git.relative_to_root(source_file),
                CI::Ext::Test::TAG_SOURCE_START => line_number.to_s
              },
              service: datadog_configuration[:service_name]
            )
          end

          def after_teardown
            test_span = CI.active_test
            return super unless test_span

            finish_with_result(test_span, result_code)
            if Helpers.parallel?(self.class)
              finish_with_result(test_span.test_suite, result_code)
            end

            super
          end

          private

          def finish_with_result(span, result_code)
            return unless span

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

          def datadog_configuration
            Datadog.configuration.ci[:minitest]
          end
        end
      end
    end
  end
end
