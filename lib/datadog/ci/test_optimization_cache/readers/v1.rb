# frozen_string_literal: true

require_relative "../../ext/test_optimization_cache"
require_relative "base"

module Datadog
  module CI
    module TestOptimizationCache
      module Readers
        class V1 < Base
          def initialize(test_optimization_path)
            @test_optimization_path = test_optimization_path
          end

          def available?
            File.exist?(settings_file_path)
          end

          def load_settings
            load_http_json(Ext::TestOptimizationCache::SETTINGS_FILE_NAME)
          end

          def load_known_tests
            load_http_json(Ext::TestOptimizationCache::KNOWN_TESTS_FILE_NAME)
          end

          def load_test_management
            load_http_json(Ext::TestOptimizationCache::TEST_MANAGEMENT_FILE_NAME)
          end

          def load_skippable_tests
            load_http_json(Ext::TestOptimizationCache::SKIPPABLE_TESTS_FILE_NAME)
          end

          private

          def load_http_json(file_name)
            read_json_file(File.join(http_cache_path, file_name))
          end

          def settings_file_path
            File.join(http_cache_path, Ext::TestOptimizationCache::SETTINGS_FILE_NAME)
          end

          def http_cache_path
            File.join(
              @test_optimization_path,
              Ext::TestOptimizationCache::CACHE_FOLDER_NAME,
              Ext::TestOptimizationCache::HTTP_CACHE_FOLDER_NAME
            )
          end
        end
      end
    end
  end
end
