# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Defines constants for test discovery mode
      module TestDiscovery
        # Default output path for test discovery mode
        DEFAULT_OUTPUT_PATH = "./.dd/test_discovery/tests.json"
        
        # Maximum buffer size before writing to file
        MAX_BUFFER_SIZE = 10_000
      end
    end
  end
end
