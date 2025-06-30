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

              dd_example_finished(notification.example)
            end

            def example_failed(notification)
              super

              dd_example_finished(notification.example)
            end

            def example_pending(notification)
              super

              dd_example_finished(notification.example)
            end

            private

            def dd_example_finished(example)
              @group_level += 1

              dd_retries_output(example)
              dd_test_management_output(example)
              dd_test_impact_analysis_output(example)

              @group_level -= 1
            end

            def dd_retries_output(example)
              if !example.metadata[Ext::METADATA_DD_RETRIES] ||
                  !CI::Ext::Test::RetryReason::DATADOG_RETRY_REASONS.include?(
                    example.metadata[Ext::METADATA_DD_RETRY_REASON]
                  )
                return
              end

              retries_count = example.metadata[Ext::METADATA_DD_RETRIES]

              output.puts(
                "#{current_indentation}| Retried #{retries_count} times by #{dd_retry_source(example.metadata[Ext::METADATA_DD_RETRY_REASON])}"
              )
              results = example.metadata[Ext::METADATA_DD_RETRY_RESULTS]
              results_output = results.map { |status, count| "#{count} / #{retries_count} #{status}" }.join(", ")
              output.puts(
                "#{current_indentation}| Results were: #{results_output}"
              )

              if results[CI::Ext::Test::Status::FAIL] > 0 && results[CI::Ext::Test::Status::PASS] > 0
                output.puts(
                  "#{current_indentation}| Flaky test detected"
                )

                @dd_flaky_tests ||= 0
                @dd_flaky_tests += 1
              end
            end

            def dd_retry_source(reason)
              case reason
              when CI::Ext::Test::RetryReason::RETRY_FAILED
                "Datadog Auto Test Retries"
              when CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY
                "Datadog Early Flake Detection"
              when CI::Ext::Test::RetryReason::RETRY_FLAKY_FIXED
                "Datadog Flaky Test Management"
              else
                "Datadog Test Optimization"
              end
            end

            def dd_test_management_output(example)
              if example.metadata[Ext::METADATA_DD_QUARANTINED]
                output.puts("#{current_indentation}| Test was quarantined by Datadog Flaky Test Management")

                @dd_quarantined_tests ||= 0
                @dd_quarantined_tests += 1
              end

              if example.metadata[Ext::METADATA_DD_DISABLED]
                output.puts("#{current_indentation}| Test was disabled by Datadog Flaky Test Management")

                @dd_disabled_tests ||= 0
                @dd_disabled_tests += 1
              end
            end

            def dd_test_impact_analysis_output(example)
              if example.metadata[Ext::METADATA_DD_SKIPPED_BY_ITR]
                @dd_skipped_by_tia_tests ||= 0
                @dd_skipped_by_tia_tests += 1
              end
            end
          end
        end
      end
    end
  end
end
