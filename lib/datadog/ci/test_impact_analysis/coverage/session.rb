# frozen_string_literal: true

require_relative "file_access"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Dependencies shared by the run, collected before any suite/context/test.
        # Loading a file is not evidence that every test depends on it: Rails and
        # many gems eagerly load their entire application. Ignore execution inside
        # require/load, and retain only conventional project helpers from boot.
        class Session
          HELPER_PATHS = %w[spec/spec_helper.rb spec/rails_helper.rb test/test_helper.rb features/support/env.rb].freeze
          LOAD_METHODS = %i[require require_relative load].freeze

          def initialize(root:, ignored_path:)
            @root = File.expand_path(root)
            @root_prefix = @root + File::SEPARATOR
            @ignored_path = File.expand_path(ignored_path) if ignored_path
            @files = {}
            @loading = Hash.new(0)
            @tracepoint = nil
            @failed = false
            @file_access = FileAccess.new(root: root, ignored_path: ignored_path,
              threading_mode: :multi, inherit_on_fork: true) { !@failed && @loading[Thread.current].zero? }
          end

          def start
            return if @tracepoint

            @failed = false
            $LOADED_FEATURES.each do |path|
              next unless path.start_with?(@root_prefix)
              next unless HELPER_PATHS.include?(path.delete_prefix(@root_prefix))

              record(path)
            end

            @tracepoint = TracePoint.new(:call, :return, :c_call, :c_return, :b_call) do |event|
              observe(event)
            rescue => e
              @failed = true
              @tracepoint&.disable
              Datadog.logger.warn("Failed to collect session coverage: #{e.class}: #{e.message}")
            end
            @tracepoint&.enable
            @file_access.start
            nil
          rescue => e
            @tracepoint&.disable
            @file_access.stop
            Datadog.logger.warn("Failed to start session coverage: #{e.class}: #{e.message}")
            nil
          end

          def stop
            @tracepoint&.disable
            @tracepoint = nil
            files = @files.merge(@file_access.stop)
            @loading.clear
            @files = {}
            files
          end

          private

          def observe(event)
            thread = Thread.current
            if LOAD_METHODS.include?(event.method_id) &&
                (event.defined_class == Kernel || event.defined_class == Kernel.singleton_class)
              case event.event
              when :call, :c_call
                @loading[thread] += 1
              when :return, :c_return
                @loading[thread] -= 1 if @loading[thread].positive?
              end
              return
            end
            return unless @loading[thread].zero?
            return unless event.event == :call || event.event == :b_call

            record(event.path)
          end

          def record(path)
            return unless path.start_with?(@root_prefix)
            ignored_path = @ignored_path
            return if ignored_path && (path == ignored_path || path.start_with?(ignored_path + File::SEPARATOR))

            @files[path] = true
          end
        end
      end
    end
  end
end
