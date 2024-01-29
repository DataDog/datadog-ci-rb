# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Cucumber integration constants
        # @public_api
        module Ext
          ENV_ENABLED = "DD_TRACE_CUCUMBER_ENABLED"
          DEFAULT_SERVICE_NAME = "cucumber"

          FRAMEWORK = "cucumber"

          STEP_SPAN_TYPE = "step"
        end
      end
    end
  end
end
