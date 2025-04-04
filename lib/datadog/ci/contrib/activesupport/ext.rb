# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module ActiveSupport
        # Datadog ActiveSupport integration constants
        module Ext
          ENV_ENABLED = "DD_CI_ACTIVESUPPORT_ENABLED"

          DEFAULT_SERVICE_NAME = "activesupport"
        end
      end
    end
  end
end
