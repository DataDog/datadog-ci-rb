# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module RSpec
        # Helper methods for RSpec instrumentation
        module Helpers
          module_function

          def parallel_tests?
            !!ENV.fetch("TEST_ENV_NUMBER", nil) && !!ENV.fetch("PARALLEL_TEST_GROUPS", nil)
          end
        end
      end
    end
  end
end
