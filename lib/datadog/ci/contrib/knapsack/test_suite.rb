# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Knapsack
        module TestSuite
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def all_test_files_to_run
              super

              return @all_test_files_to_run if @_dd_filtering_applied

              @_dd_filtering_applied = true

              if adapter_class.respond_to?(:_dd_discover_test_examples)
                adapter_class._dd_discover_test_examples

                # filter test files here
              end

              @all_test_files_to_run
            end
          end
        end
      end
    end
  end
end
