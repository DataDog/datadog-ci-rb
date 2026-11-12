# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module FileAccess
        module Instrumentation
          def self.active_test
            return if Thread.current.thread_variable_get(:dd_recording_file_dependency)

            components = Datadog.send(:components, allow_initialization: false)
            components.test_tracing.active_test if components&.test_impact_analysis&.code_coverage?
          rescue => e
            warn_failure(e)
            nil
          end

          def self.warn_failure(error)
            Thread.current.thread_variable_set(:dd_recording_file_dependency, true)
            Datadog.logger.warn("Failed to collect file dependency: #{error}")
          rescue
            nil
          ensure
            Thread.current.thread_variable_set(:dd_recording_file_dependency, false)
          end

          module InstanceMethods
            # Also covers File.open and local-file Kernel.open, before their blocks run.
            def initialize(*args, **options)
              super
              if (test = Instrumentation.active_test)
                Datadog.send(:components).test_impact_analysis.record_file_dependency(test, self)
              end
            end
          end

          module ClassMethods
            # Ruby opens these directly in C, bypassing File#initialize.
            def read(path, *args, **options, &block)
              if (test = Instrumentation.active_test)
                # Coerce once, preserving the caller's conversion and IO exceptions.
                path = ::File.path(path)
                Datadog.send(:components).test_impact_analysis.record_file_dependency(test, path)
              end
              super
            end

            def binread(path, *args, **options, &block)
              if (test = Instrumentation.active_test)
                path = ::File.path(path)
                Datadog.send(:components).test_impact_analysis.record_file_dependency(test, path)
              end
              super
            end
          end
        end
      end
    end
  end
end
