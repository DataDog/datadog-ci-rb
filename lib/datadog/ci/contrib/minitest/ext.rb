# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        # Minitest integration constants
        # @public_api
        module Ext
          ENV_ENABLED = "DD_TRACE_MINITEST_ENABLED"

          FRAMEWORK = "minitest"

          DEFAULT_SERVICE_NAME = "minitest"
        end
      end
    end
  end
end
