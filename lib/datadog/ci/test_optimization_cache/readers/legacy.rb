# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../ext/test_optimization_cache"
require_relative "base"

module Datadog
  module CI
    module TestOptimizationCache
      module Readers
        class Legacy < Base
          def load_settings
            load_legacy_json(Ext::TestOptimizationCache::SETTINGS_FILE_NAME)
          end

          def load_known_tests
            payload = load_legacy_json(Ext::TestOptimizationCache::KNOWN_TESTS_FILE_NAME)
            backend_response(payload) if payload
          end

          def load_test_management
            payload = load_legacy_json(Ext::TestOptimizationCache::LEGACY_TEST_MANAGEMENT_TESTS_FILE_NAME)
            backend_response(payload) if payload
          end

          def load_skippable_tests
            payload = load_legacy_json(Ext::TestOptimizationCache::SKIPPABLE_TESTS_FILE_NAME)
            skippable_tests_response(payload) if payload
          end

          private

          def load_legacy_json(file_name)
            read_json_file(File.join(Ext::TestOptimizationCache::TESTOPTIMIZATION_CACHE_PATH, file_name))
          end

          def backend_response(payload)
            {
              "data" => {
                "attributes" => payload
              }
            }
          end

          def skippable_tests_response(payload)
            skippable_tests = payload.fetch("skippableTests", {}) || {}

            data = skippable_tests.each_value.flat_map do |tests_hash|
              tests_hash.each_value.flat_map do |test_configs|
                test_configs.map do |test_config|
                  {
                    "type" => Ext::Test::DEFAULT_TIA_TEST_SKIPPING_MODE,
                    "attributes" => {
                      "suite" => test_config["suite"],
                      "name" => test_config["name"],
                      "parameters" => test_config["parameters"]
                    }
                  }
                end
              end
            end

            {
              "meta" => {
                "correlation_id" => payload["correlationId"]
              },
              "data" => data
            }
          end
        end
      end
    end
  end
end
