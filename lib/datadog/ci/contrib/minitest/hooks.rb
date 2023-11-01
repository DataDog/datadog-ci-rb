# frozen_string_literal: true

require_relative "../../recorder"
require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Lifecycle hooks to instrument Minitest::Test
        module Hooks
          def before_setup
            super
            return unless configuration[:enabled]

            test_name = "#{class_name}##{name}"

            path, = method(name).source_location
            test_suite = Pathname.new(path.to_s).relative_path_from(Pathname.pwd).to_s

            test_span = CI.trace_test(
              test_name,
              tags: {
                framework: Ext::FRAMEWORK,
                framework_version: CI::Contrib::Minitest::Integration.version.to_s,
                test_type: Ext::TEST_TYPE,
                test_suite: test_suite
              },
              service_name: configuration[:service_name],
              operation_name: configuration[:operation_name]
            )

            @current_test_span = test_span
          end

          def after_teardown
            return super unless @current_test_span

            Thread.current[:_datadog_test_span] = nil

            case result_code
            when "."
              @current_test_span.passed!
            when "E", "F"
              @current_test_span.failed!(failure)
            when "S"
              @current_test_span.skipped!(nil, failure.message)
            end

            @current_test_span.finish
            @current_test_span = nil

            super
          end

          private

          def configuration
            ::Datadog.configuration.ci[:minitest]
          end
        end
      end
    end
  end
end
