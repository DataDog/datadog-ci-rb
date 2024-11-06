# frozen_string_literal: true

require_relative "../patcher"

require_relative "ext"
require_relative "rum"
require_relative "../../ext/test"

module Datadog
  module CI
    module Contrib
      module Selenium
        # instruments Selenium::WebDriver::Driver
        module Driver
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def quit
              return super unless datadog_configuration[:enabled]

              Datadog.logger.debug("[Selenium] Driver quit event")

              RUM.stop_rum_session(@bridge)

              Datadog.logger.debug("[Selenium] RUM session stopped, deleting cookie")
              @bridge.manage.delete_cookie(Ext::COOKIE_TEST_EXECUTION_ID)
            rescue ::Selenium::WebDriver::Error::WebDriverError => e
              Datadog.logger.debug("[Selenium] Error while quitting Selenium driver: #{e.message}")
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
