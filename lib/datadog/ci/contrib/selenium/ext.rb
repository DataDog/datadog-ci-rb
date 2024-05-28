# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Selenium
        # Selenium integration constants
        # @public_api
        module Ext
          ENV_ENABLED = "DD_CIVISIBILITY_SELENIUM_ENABLED"
          ENV_RUM_FLUSH_WAIT_MILLIS = "DD_CIVISIBILITY_RUM_FLUSH_WAIT_MILLIS"

          COOKIE_TEST_EXECUTION_ID = "datadog-ci-visibility-test-execution-id"

          SCRIPT_IS_RUM_ACTIVE = <<~JS
            return !!window.DD_RUM
          JS
          SCRIPT_STOP_RUM_SESSION = <<~JS
            if (window.DD_RUM && window.DD_RUM.stopSession) {
              window.DD_RUM.stopSession();
              return true;
            } else {
            	return false;
            }
          JS
        end
      end
    end
  end
end
