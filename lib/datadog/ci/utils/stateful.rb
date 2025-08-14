# frozen_string_literal: true

require_relative "file_storage"
require_relative "../ext/test_runner"

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
          # Check for Datadog Test Runner context first
          if Dir.exist?(Ext::TestRunner::DATADOG_CONTEXT_PATH)
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
      end
    end
  end
end
