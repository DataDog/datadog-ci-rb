# frozen_string_literal: true

require_relative "test_optimization_cache"

module Datadog
  module CI
    module Ext
      # Defines constants for test discovery mode
      module TestDiscovery
        # Default output path for test discovery mode
        DEFAULT_OUTPUT_PATH = "./#{TestOptimizationCache::PLAN_FOLDER}/test_discovery/tests.json"

        # Maximum buffer size before writing to file
        MAX_BUFFER_SIZE = 10_000
      end
    end
  end
end
