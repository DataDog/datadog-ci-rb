# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

require_relative "ext"

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
            end
          end
        end
      end
    end
  end
end
