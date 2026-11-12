# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module FileAccess
        module Instrumentation
          def self.test_impact_analysis
            Datadog.send(:components, allow_initialization: false)&.test_impact_analysis
          rescue => error
            # The component/logger may be inaccessible (for example in a Ractor).
            # Use stderr here so reporting cannot re-enter the File hooks.
            begin
              Kernel.warn("Failed to access file dependency instrumentation: #{error}")
            rescue
              nil
            end
            nil
          end

          module InstanceMethods
            # Also covers File.open and local-file Kernel.open, before their blocks run.
            def initialize(*args)
              super
              Instrumentation.test_impact_analysis&.record_file_dependency(self)
            end
            ruby2_keywords(:initialize)
          end

          module ClassMethods
            # Ruby opens these directly in C, bypassing File#initialize.
            def read(path, *args)
              component = Instrumentation.test_impact_analysis
              path = component.prepare_file_read(path) if component
              super
            end
            ruby2_keywords(:read)

            def binread(path, *args)
              component = Instrumentation.test_impact_analysis
              path = component.prepare_file_read(path) if component
              super
            end
            ruby2_keywords(:binread)
          end
        end
      end
    end
  end
end
