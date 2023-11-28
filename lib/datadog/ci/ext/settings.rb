# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      # Defines constants for test tags
      module Settings
        ENV_MODE_ENABLED = "DD_TRACE_CI_ENABLED"
        ENV_AGENTLESS_MODE_ENABLED = "DD_CIVISIBILITY_AGENTLESS_ENABLED"
        ENV_AGENTLESS_URL = "DD_CIVISIBILITY_AGENTLESS_URL"
        ENV_EXPERIMENTAL_TEST_SUITE_LEVEL_VISIBILITY_ENABLED = "DD_CIVISIBILITY_EXPERIMENTAL_TEST_SUITE_LEVEL_VISIBILITY_ENABLED"
      end
    end
  end
end
