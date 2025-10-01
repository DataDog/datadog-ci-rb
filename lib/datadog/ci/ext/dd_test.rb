# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Constants for integration with DDTest tool: https://github.com/DataDog/ddtest
      module DDTest
        PLAN_FOLDER = ".testoptimization"
        TESTOPTIMIZATION_CACHE_PATH = "#{PLAN_FOLDER}/cache"

        SETTINGS_FILE_NAME = "settings.json"
        KNOWN_TESTS_FILE_NAME = "known_tests.json"
        TEST_MANAGEMENT_TESTS_FILE_NAME = "test_management_tests.json"
        SKIPPABLE_TESTS_FILE_NAME = "skippable_tests.json"
      end
    end
  end
end
