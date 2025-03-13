# frozen_string_literal: true

require_relative "../../ext/settings"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        module Runner
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def execute_command(cmd, process_number, num_processes, options)
              super
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end
          end
        end
      end
    end
  end
end
