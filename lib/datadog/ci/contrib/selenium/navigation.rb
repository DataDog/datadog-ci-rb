# frozen_string_literal: true

require_relative "../patcher"

require_relative "ext"
require_relative "../../ext/test"

module Datadog
  module CI
    module Contrib
      module Selenium
        # instruments Selenium::WebDriver::Navigation
        module Navigation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def to(url)
              result = super

              return result unless datadog_configuration[:enabled]

              Datadog.logger.debug("[Selenium] Navigation to #{url}")

              # on session reset Capybara navigates to about:blank
              return result if url == "about:blank"

              active_test = Datadog::CI.active_test
              Datadog.logger.debug("[Selenium] Active test: #{active_test}")

              return result unless active_test

              # Set the test's trace id as a cookie in browser session
              cookie_hash = {name: Ext::COOKIE_TEST_EXECUTION_ID, value: active_test.trace_id.to_s}
              Datadog.logger.debug { "[Selenium] Setting cookie: #{cookie_hash}" }
              @bridge.manage.add_cookie(cookie_hash)

              # set the test type to browser
              active_test.set_tag(CI::Ext::Test::TAG_TYPE, CI::Ext::Test::Type::BROWSER)

              # set the tags specific to the browser test
              active_test.set_tag(CI::Ext::Test::TAG_BROWSER_DRIVER, "selenium")
              active_test.set_tag(
                CI::Ext::Test::TAG_BROWSER_DRIVER_VERSION,
                datadog_integration.version
              )
              active_test.set_tag(
                CI::Ext::Test::TAG_BROWSER_NAME,
                @bridge.browser
              )
              active_test.set_tag(
                CI::Ext::Test::TAG_BROWSER_VERSION,
                @bridge.capabilities.browser_version
              )

              result
            rescue ::Selenium::WebDriver::Error::WebDriverError => e
              Datadog.logger.debug("[Selenium] Error while navigating: #{e.message}")

              result
            end

            private

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:selenium)
            end

            def datadog_configuration
              Datadog.configuration.ci[:selenium]
            end
          end
        end
      end
    end
  end
end
