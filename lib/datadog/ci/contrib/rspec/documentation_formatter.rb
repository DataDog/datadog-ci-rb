module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::Formatters::DocumentationFormatter
        module DocumentationFormatter
          DATADOG_RETRY_REASONS = [
            CI::Ext::Test::RetryReason::RETRY_FAILED,
            CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY,
            CI::Ext::Test::RetryReason::RETRY_FLAKY_FIXED
          ]

          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def example_passed(notification)
              super

              retries_output(notification.example)
            end

            def example_failed(notification)
              super

              retries_output(notification.example)
            end

            def retries_output(example)
              return if !example.metadata[:dd_retries] || !DATADOG_RETRY_REASONS.include?(example.metadata[:dd_retry_reason])

              output.puts "Retried #{example.metadata[:dd_retries]} times by #{retry_source(example.metadata[:dd_retry_reason])}"
              # TODO: retry results
              # TODO: Was it flaky????
              # TODO: was it attempt to fix? if yes - did it fail all retries or was it a success or is it still flaky?
            end

            def retry_source(reason)
              case reason
              when CI::Ext::Test::RetryReason::RETRY_FAILED
                "Datadog Auto Test Retries"
              when CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY
                "Datadog Early Flake Detection"
              when CI::Ext::Test::RetryReason::RETRY_FLAKY_FIXED
                "Datadog Flaky Test Management"
              end
            end
          end
        end
      end
    end
  end
end
