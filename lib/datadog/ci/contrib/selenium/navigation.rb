# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

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
              super

              # on session reset Capybara navigates to about:blank
              return if url == "about:blank"

              active_test = Datadog::CI.active_test
              return unless active_test

              # Set the test's trace id as a cookie in browser session
              @bridge.manage.add_cookie(name: Ext::COOKIE_TEST_EXECUTION_ID, value: active_test.trace_id.to_s)

              # set the test type to browser
              active_test.set_tag(CI::Ext::Test::TAG_TYPE, CI::Ext::Test::Type::BROWSER)

              # set the tags specific to the browser test
              active_test.set_tag(CI::Ext::Test::TAG_BROWSER_DRIVER, "selenium")
              active_test.set_tag(
                CI::Ext::Test::TAG_BROWSER_DRIVER_VERSION,
                Integration.version
              )
              active_test.set_tag(
                CI::Ext::Test::TAG_BROWSER_NAME,
                @bridge.browser
              )
              active_test.set_tag(
                CI::Ext::Test::TAG_BROWSER_VERSION,
                @bridge.capabilities.browser_version
              )

              is_rum_active_result = @bridge.execute_script(Ext::SCRIPT_IS_RUM_ACTIVE)
              if is_rum_active_result == "true"
                active_test.set_tag(
                  CI::Ext::Test::TAG_IS_RUM_ACTIVE,
                  "true"
                )
              end
            end
          end
        end
      end
    end
  end
end
