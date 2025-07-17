# frozen_string_literal: true

module Datadog
  module CI
    module TestDiscovery
      # Test discovery mode component that manages test discovery output and lifecycle
      class Component
        def initialize(
          enabled:,
          output_path:
        )
          @enabled = enabled
          @output_path = output_path
        end

        def configure(library_settings, test_session)
          # This method is noop for this component, it is present for compatibility with other components
        end

        def disable_features_for_test_discovery!(settings)
          return unless @enabled

          # Disable all feature flags when in test discovery mode
          settings.telemetry.enabled = false
          settings.ci.itr_enabled = false
          settings.ci.git_metadata_upload_enabled = false
          settings.ci.retry_failed_tests_enabled = false
          settings.ci.retry_new_tests_enabled = false
          settings.ci.test_management_enabled = false
          settings.ci.agentless_logs_submission_enabled = false
          settings.ci.impacted_tests_detection_enabled = false
        end

        def shutdown!
        end
      end
    end
  end
end
