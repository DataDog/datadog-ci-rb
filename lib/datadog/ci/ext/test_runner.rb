# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Constants for integration with Datadog Test Runner: https://github.com/DataDog/datadog-test-runner
      module TestRunner
        DATADOG_CONTEXT_PATH = ".dd/context"
        SETTINGS_FILE_NAME = "settings.json"
      end
    end
  end
end
