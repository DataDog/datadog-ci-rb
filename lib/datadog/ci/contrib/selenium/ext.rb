# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Selenium
        # Selenium integration constants
        # @public_api
        module Ext
          ENV_ENABLED = "DD_CIVISIBILITY_SELENIUM_ENABLED"

          COOKIE_TEST_EXECUTION_ID = "datadog-ci-visibility-test-execution-id"

          SCRIPT_IS_RUM_ACTIVE = <<~JS
            return !!window.DD_RUM
          JS
        end
      end
    end
  end
end
