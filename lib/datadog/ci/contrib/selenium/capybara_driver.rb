# frozen_string_literal: true

require_relative "../patcher"

require_relative "../../ext/rum"
require_relative "../../ext/test"
require_relative "../../utils/rum"

module Datadog
  module CI
    module Contrib
      module Selenium
        # instruments Capybara::Selenium::Driver
        module CapybaraDriver
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def reset!
              return super unless datadog_configuration[:enabled]

              Datadog.logger.debug("[Selenium] Capybara session reset event")

              Utils::RUM.stop_rum_session(@browser)

              Datadog.logger.debug("[Selenium] RUM session stopped, deleting cookie")
              @browser.manage.delete_cookie(CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID)
            rescue ::Selenium::WebDriver::Error::WebDriverError => e
              Datadog.logger.debug("[Selenium] Error while resetting Capybara session: #{e.message}")
            ensure
              super
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:selenium]
            end
          end
        end
      end
    end
  end
end
