# frozen_string_literal: true

require_relative "../patcher"

require_relative "../../ext/rum"
require_relative "../../ext/test"
require_relative "../../utils/rum"

module Datadog
  module CI
    module Contrib
      module Cuprite
        # instruments Capybara::Cuprite::Driver
        module Driver
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def visit(url)
              result = super

              return result unless datadog_configuration[:enabled]

              Datadog.logger.debug("[Cuprite] Navigation to #{url}")

              # on session reset Capybara navigates to about:blank
              return result if url == "about:blank"

              active_test = Datadog::CI.active_test
              Datadog.logger.debug("[Cuprite] Active test: #{active_test}")

              return result unless active_test

              # Set the test's trace id as a cookie in browser session
              Datadog.logger.debug do
                "[Cuprite] Setting cookie #{CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID} to #{active_test.trace_id}"
              end
              set_cookie(CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID, active_test.trace_id.to_s)

              # set the test type to browser
              active_test.set_tag(CI::Ext::Test::TAG_TYPE, CI::Ext::Test::Type::BROWSER)

              # set the tags specific to the browser test
              active_test.set_tag(CI::Ext::Test::TAG_BROWSER_DRIVER, "cuprite")
              active_test.set_tag(CI::Ext::Test::TAG_BROWSER_DRIVER_VERSION, datadog_integration.version)
              active_test.set_tag(CI::Ext::Test::TAG_BROWSER_NAME, browser.options.browser_name || "chrome")
              active_test.set_tag(CI::Ext::Test::TAG_BROWSER_VERSION, browser.version.product)

              result
            end

            def reset!
              datadog_end_rum_session

              super
            end

            def quit
              datadog_end_rum_session

              super
            end

            private

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:cuprite)
            end

            def datadog_configuration
              Datadog.configuration.ci[:cuprite]
            end

            def datadog_end_rum_session
              return unless datadog_configuration[:enabled]

              Datadog.logger.debug("[Cuprite] Driver quit event")

              Utils::RUM.stop_rum_session(self)

              Datadog.logger.debug("[Cuprite] RUM session stopped, deleting cookie")
              remove_cookie(CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID)
            end
          end
        end
      end
    end
  end
end
