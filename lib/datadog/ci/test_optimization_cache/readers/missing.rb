# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestOptimizationCache
      module Readers
        class Missing < Base
          def available?
            false
          end

          def load_settings
            nil
          end

          def load_known_tests
            nil
          end

          def load_test_management
            nil
          end

          def load_skippable_tests
            nil
          end
        end
      end
    end
  end
end
