# frozen_string_literal: true

module Datadog
  module CI
    module Remote
      # No-op implementation used when remote configuration is disabled.
      class NullComponent
        def configure(_test_session)
        end
      end
    end
  end
end
