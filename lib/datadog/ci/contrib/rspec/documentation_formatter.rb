module Datadog
  module CI
    module Contrib
      module RSpec
        # Instrument RSpec::Core::Formatters::DocumentationFormatter
        module DocumentationFormatter
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
              if !example.metadata[:dd_retries] ||
                  !CI::Ext::Test::RetryReason::DATADOG_RETRY_REASONS.include?(
                    example.metadata[:dd_retry_reason]
                  )
                return
              end

              @group_level += 1

              output.puts(
                "#{current_indentation}| Retried #{example.metadata[:dd_retries]} times by #{retry_source(example.metadata[:dd_retry_reason])}"
              )
              output.puts(
                "#{current_indentation}| Results were: #{example.metadata[:dd_results].map { |status, count| "#{count} / #{example.metadata[:dd_retries]} #{status}" }.join(", ")}"
              )
              # TODO: Was it flaky????
              # TODO: was it attempt to fix? if yes - did it fail all retries or was it a success or is it still flaky?

              @group_level -= 1
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
