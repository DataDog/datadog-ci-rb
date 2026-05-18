# frozen_string_literal: true

module Datadog
  module CI
    module TestOptimizationCache
      class NullComponent
        def cache_available?
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

        def shutdown!
        end
      end
    end
  end
end
