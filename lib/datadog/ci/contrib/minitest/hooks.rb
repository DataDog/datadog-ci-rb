# frozen_string_literal: true

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

            CI.start_test(
              test_name,
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Minitest::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => Ext::TEST_TYPE,
                CI::Ext::Test::TAG_SUITE => test_suite
              },
              service_name: configuration[:service_name],
              operation_name: configuration[:operation_name]
            )
          end

          def after_teardown
            test_span = CI.active_test
            return super unless test_span

            case result_code
            when "."
              test_span.passed!
            when "E", "F"
              test_span.failed!(exception: failure)
            when "S"
              test_span.skipped!(reason: failure.message)
            end

            test_span.finish

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
