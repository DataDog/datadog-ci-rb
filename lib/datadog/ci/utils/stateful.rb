# frozen_string_literal: true

require "json"
require_relative "file_storage"
require_relative "../ext/dd_test"

module Datadog
  module CI
    module Utils
      # Module for components that need to persist and restore state
      module Stateful
        # Store component state
        def store_component_state
          state = serialize_state

          res = Utils::FileStorage.store(storage_key, state)
          Datadog.logger.debug { "Stored component state (key=#{storage_key}): #{res}" }

          res
        end

        # Load component state
        def load_component_state
          # Check for DDTest cache first
          if Dir.exist?(Ext::DDTest::TESTOPTIMIZATION_CACHE_PATH)
            Datadog.logger.debug { "DDTest cache found" }
            return true if restore_state_from_datadog_test_runner
          end

          test_visibility_component = Datadog.send(:components).test_visibility
          return false unless test_visibility_component.client_process?

          state = Utils::FileStorage.retrieve(storage_key)
          unless state
            Datadog.logger.debug { "No component state found in file storage (key=#{storage_key})" }
            return false
          end

          restore_state(state)
          Datadog.logger.debug { "Loaded component state from file storage (key=#{storage_key})" }

          true
        end

        # These methods must be implemented by including classes
        def serialize_state
          raise NotImplementedError, "Components must implement #serialize_state"
        end

        def restore_state(state)
          raise NotImplementedError, "Components must implement #restore_state"
        end

        def storage_key
          raise NotImplementedError, "Components must implement #storage_key"
        end

        def restore_state_from_datadog_test_runner
          false
        end

        def load_json(file_name)
          file_path = File.join(Ext::DDTest::TESTOPTIMIZATION_CACHE_PATH, file_name)

          unless File.exist?(file_path)
            Datadog.logger.debug { "JSON file not found: #{file_path}" }
            return nil
          end

          content = File.read(file_path)
          JSON.parse(content)
        rescue JSON::ParserError => e
          Datadog.logger.debug { "Failed to parse JSON file #{file_path}: #{e.message}" }
          nil
        rescue => e
          Datadog.logger.debug { "Failed to load JSON file #{file_path}: #{e.message}" }
          nil
        end
      end
    end
  end
end
