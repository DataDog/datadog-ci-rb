# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module ParallelTests
        # Datadog ParallelTests integration constants
        module Ext
          ENV_ENABLED = "DD_TRACE_PARALLEL_TESTS_ENABLED"

          DEFAULT_SERVICE_NAME = "parallel_tests"
        end
      end
    end
  end
end
