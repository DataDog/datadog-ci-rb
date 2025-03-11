# frozen_string_literal: true

require_relative "../../../core/utils/only_once"

module Datadog
  module CI
    module Contrib
      module ParallelTests
        # Datadog ParallelTests integration constants
        module Ext
          ENV_ENABLED = "DD_TRACE_PARALLEL_TESTS_ENABLED"
        end
      end
    end
  end
end
