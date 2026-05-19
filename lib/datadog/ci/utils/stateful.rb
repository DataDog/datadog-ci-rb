# frozen_string_literal: true

require_relative "file_storage"

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
          if test_optimization_cache.cache_available?
            Datadog.logger.debug { "Test Optimization cache found" }
            return true if restore_state_from_datadog_test_runner
          end

          test_tracing_component = Datadog.send(:components).test_tracing
          return false unless test_tracing_component.client_process?

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

        def load_cached_settings
          test_optimization_cache.load_settings
        end

        def load_cached_known_tests
          test_optimization_cache.load_known_tests
        end

        def load_cached_test_management
          test_optimization_cache.load_test_management
        end

        def load_cached_skippable_tests
          test_optimization_cache.load_skippable_tests
        end

        def test_optimization_cache
          Datadog.send(:components).test_optimization_cache
        end
      end
    end
  end
end
