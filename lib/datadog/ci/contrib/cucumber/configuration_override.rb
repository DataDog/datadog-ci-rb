# frozen_string_literal: true

require_relative "formatter"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Changes behaviour of Cucumber::Configuration class
        module ConfigurationOverride
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for configuration
          module InstanceMethods
            def retry_attempts
              super if !datadog_test_retries_component&.retry_failed_tests_enabled

              datadog_test_retries_component&.retry_failed_tests_max_attempts
            end

            def retry_total_tests
              super
            end

            def datadog_test_retries_component
              Datadog.send(:components).test_retries
            end
          end
        end
      end
    end
  end
end
