# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Simplecov
        # Simplecov integration constants
        # @public_api
        module Ext
          ENV_ENABLED = "DD_CIVISIBILITY_SIMPLECOV_INSTRUMENTATION_ENABLED"

          COVERAGE_FORMAT = "simplecov-internal"
        end
      end
    end
  end
end
