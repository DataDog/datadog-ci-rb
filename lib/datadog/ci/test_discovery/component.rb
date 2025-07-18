# frozen_string_literal: true

require "fileutils"

require_relative "../ext/test"
require_relative "../ext/test_discovery"

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
          @output_stream = nil
        end

        def configure(library_settings, test_session)
          # This method is noop for this component, it is present for compatibility with other components
        end

        def disable_features_for_test_discovery!(settings)
          return unless @enabled

          # in test discovery mode don't send anything to Datadog
          settings.ci.discard_traces = true

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

        def on_test_session_start
          return unless @enabled

          if @output_path.nil? || @output_path&.empty?
            @output_path = Ext::TestDiscovery::DEFAULT_OUTPUT_PATH
          end

          # thanks RBS for this weirdness
          output_path = @output_path
          return unless output_path

          output_dir = File.dirname(output_path)
          FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

          @output_stream = File.open(output_path, "w")
        end

        def on_test_session_end
          return unless @enabled

          @output_stream&.close
          @output_stream = nil
        end

        def on_test_started(test)
          return unless @enabled

          # Mark test as being in test discovery mode so it will be skipped
          test.mark_test_discovery_mode!
        end

        def shutdown!
          if @output_stream && !@output_stream&.closed?
            @output_stream&.close
            @output_stream = nil
          end
        end
      end
    end
  end
end
