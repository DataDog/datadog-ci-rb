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
        end
      end
    end
  end
end
