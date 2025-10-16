# frozen_string_literal: true

require "fileutils"
require "json"
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

          @buffer = []
          @buffer_mutex = Mutex.new
        end

        def configure(library_settings, test_session)
          # This method is noop for this component, it is present for compatibility with other components
        end

        def enabled?
          @enabled
        end

        def disable_features_for_test_discovery!(settings)
          return unless @enabled

          Datadog.logger.debug("ATTENTION! Running in test discovery mode, disabling all features")

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

        def start
          return unless @enabled

          if @output_path.nil? || @output_path&.empty?
            @output_path = Ext::TestDiscovery::DEFAULT_OUTPUT_PATH
          end

          # thanks RBS for this weirdness
          output_path = @output_path
          return unless output_path

          output_dir = File.dirname(output_path)
          FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

          Datadog.logger.debug { "Test discovery output path: #{output_path}" }

          @buffer_mutex.synchronize { @buffer.clear }
        end

        def finish
          return unless @enabled

          @buffer_mutex.synchronize do
            flush_buffer_unsafe if @buffer.any?
          end
        end

        def record_test(name:, suite:, module_name:, parameters:, source_file:)
          test_info = {
            "name" => name,
            "suite" => suite,
            "module" => module_name,
            "parameters" => parameters,
            "suiteSourceFile" => source_file
          }

          Datadog.logger.debug { "Discovered test: #{test_info}" }

          @buffer_mutex.synchronize do
            @buffer << test_info

            flush_buffer_unsafe if @buffer.size >= Ext::TestDiscovery::MAX_BUFFER_SIZE
          end
        end

        def shutdown!
          return unless @enabled

          @buffer_mutex.synchronize do
            flush_buffer_unsafe if @buffer.any?
          end
        end

        private

        # Unsafe version - caller must hold @buffer_mutex
        def flush_buffer_unsafe
          return unless @output_path && @buffer.any?

          output_path = @output_path
          return unless output_path

          Datadog.logger.debug { "Flushing test discovery buffer with #{@buffer.size} entries to #{output_path}" }

          File.open(output_path, "a") do |file|
            # disk IO latency is much bigger than time to serialize 10k JSON objects, so we do it in memory and then write to disk
            json_lines = @buffer.map { |test_info| JSON.generate(test_info) }
            file.puts(json_lines)
          end

          @buffer.clear
        end
      end
    end
  end
end
