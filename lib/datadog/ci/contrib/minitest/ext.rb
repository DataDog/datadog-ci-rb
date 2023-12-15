# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        # Minitest integration constants
        # TODO: mark as `@public_api` when GA, to protect from resource and tag name changes.
        module Ext
          ENV_ENABLED = "DD_TRACE_MINITEST_ENABLED"

          FRAMEWORK = "minitest"

          DEFAULT_SERVICE_NAME = "minitest"

          # TODO: remove in 1.0
          ENV_OPERATION_NAME = "DD_TRACE_MINITEST_OPERATION_NAME"
          OPERATION_NAME = "minitest.test"
        end
      end
    end
  end
end
