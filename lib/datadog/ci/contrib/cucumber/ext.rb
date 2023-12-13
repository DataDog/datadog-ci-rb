# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Cucumber integration constants
        # TODO: mark as `@public_api` when GA, to protect from resource and tag name changes.
        module Ext
          ENV_ENABLED = "DD_TRACE_CUCUMBER_ENABLED"
          DEFAULT_SERVICE_NAME = "cucumber"

          FRAMEWORK = "cucumber"

          STEP_SPAN_TYPE = "step"

          # TODO: remove in 1.0
          ENV_OPERATION_NAME = "DD_TRACE_CUCUMBER_OPERATION_NAME"
          OPERATION_NAME = "cucumber.test"
        end
      end
    end
  end
end
