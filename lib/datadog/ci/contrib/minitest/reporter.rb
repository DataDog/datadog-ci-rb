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
            def report(*)
              return super unless datadog_configuration[:enabled]

              res = super

              active_test_session = CI.active_test_session
              active_test_module = CI.active_test_module

              return res if active_test_session.nil? || active_test_module.nil?

              if passed?
                active_test_module.passed!
                active_test_session.passed!
              else
                active_test_module.failed!
                active_test_session.failed!
              end

              active_test_module.finish
              active_test_session.finish

              res
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end
          end
        end
      end
    end
  end
end
