# frozen_string_literal: true

module Datadog
  module CI
    module Remote
      # No-op implementation used when remote configuration is disabled.
      class NullComponent
        FILE_STORAGE_KEY = "remote_component_state"

        def configure(_test_session)
        end

        def serialize_state
          {}
        end

        def restore_state(_state)
        end

        def storage_key
          FILE_STORAGE_KEY
        end

        def restore_state_from_datadog_test_runner
          false
        end
      end
    end
  end
end
