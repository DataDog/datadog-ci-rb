# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Reporter
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def report(*args)
              return super unless datadog_configuration[:enabled]

              res = super

              active_test_session = CI.active_test_session
              active_test_module = CI.active_test_module

              return res if active_test_session.nil? || active_test_module.nil?

              if !passed?
                active_test_module.failed!
                active_test_session.failed!
              elsif !test_tracing_component.any_tests_started?
                active_test_module.skipped!(reason: "No tests were executed")
                active_test_session.skipped!(reason: "No tests were executed")
                active_test_module.set_tag(CI::Ext::Test::TAG_SESSION_EMPTY_REASON, "zero_tests")
                active_test_session.set_tag(CI::Ext::Test::TAG_SESSION_EMPTY_REASON, "zero_tests")
              else
                active_test_module.passed!
                active_test_session.passed!
              end

              active_test_module.finish
              active_test_session.finish

              res
            end

            private

            def test_tracing_component
              Datadog.send(:components).test_tracing
            end

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end
          end
        end
      end
    end
  end
end
