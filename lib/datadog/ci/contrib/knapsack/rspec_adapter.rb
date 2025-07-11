# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Knapsack
        module RSpecAdapter
          def self.included(base)
            require_relative "test_example_detector"

            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def _dd_discover_test_examples
              CI::Contrib::Knapsack::TestExampleDetector.new._dd_generate_json_report(ENV["KNAPSACK_PRO_RSPEC_OPTIONS"])
            end
          end
        end
      end
    end
  end
end
