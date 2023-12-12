# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module RSpec
        # RSpec integration constants
        # TODO: mark as `@public_api` when GA, to protect from resource and tag name changes.
        module Ext
          FRAMEWORK = "rspec"
          DEFAULT_SERVICE_NAME = "rspec"

          ENV_ENABLED = "DD_TRACE_RSPEC_ENABLED"

          # TODO: remove in 1.0
          ENV_OPERATION_NAME = "DD_TRACE_RSPEC_OPERATION_NAME"
          OPERATION_NAME = "rspec.example"
        end
      end
    end
  end
end
