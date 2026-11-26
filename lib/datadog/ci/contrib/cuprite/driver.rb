# frozen_string_literal: true

require "uri"

require_relative "script_executor"
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
              datadog_tag_navigation(url)
              result
            end

            def reset!
              datadog_end_rum_session("reset!")
              super
            end

            def quit
              datadog_end_rum_session("quit")
              super
            end

            private

            def datadog_tag_navigation(url)
              return unless datadog_configuration[:enabled]

              Datadog.logger.debug("[Cuprite] Navigation to #{url}")

              # on session reset Capybara navigates to about:blank
              return if url == "about:blank"

              active_test = Datadog::CI.active_test
              Datadog.logger.debug("[Cuprite] Active test: #{active_test}")

              return unless active_test

              # Set the test's trace id as a cookie in browser session
              Datadog.logger.debug do
                "[Cuprite] Setting cookie #{CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID} to #{active_test.trace_id}"
              end
              browser.cookies.set(
                name: CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID,
                value: active_test.trace_id.to_s,
                domain: URI.parse(browser.current_url).host
              )

              # set the test type to browser
              active_test.set_internal_tag(CI::Ext::Test::TAG_TYPE, CI::Ext::Test::Type::BROWSER)

              # set the tags specific to the browser test
              active_test.set_internal_tag(CI::Ext::Test::TAG_BROWSER_DRIVER, "cuprite")
              active_test.set_internal_tag(CI::Ext::Test::TAG_BROWSER_DRIVER_VERSION, datadog_integration.version)
              active_test.set_internal_tag(CI::Ext::Test::TAG_BROWSER_NAME, browser.options.to_h[:browser_name] || "chrome")
              active_test.set_internal_tag(CI::Ext::Test::TAG_BROWSER_VERSION, browser.version.product)
            rescue => e
              Datadog.logger.warn("[Cuprite] Could not record browser navigation: #{e.class}: #{e.message}")
            end

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:cuprite)
            end

            def datadog_configuration
              Datadog.configuration.ci[:cuprite]
            end

            def datadog_end_rum_session(event)
              active_browser = @browser
              return unless active_browser && datadog_configuration[:enabled]

              Datadog.logger.debug("[Cuprite] Driver #{event} event")
              executor = ScriptExecutor.new(active_browser)
              Utils::RUM.stop_rum_session(executor, rum_flush_wait_millis: datadog_configuration[:rum_flush_wait_millis])

              domain = URI.parse(active_browser.current_url).host
              return unless domain

              Datadog.logger.debug("[Cuprite] Deleting Datadog cookie")
              active_browser.cookies.remove(name: CI::Ext::RUM::COOKIE_TEST_EXECUTION_ID, domain: domain)
            rescue => e
              Datadog.logger.warn("[Cuprite] Could not end the RUM session during #{event}: #{e.class}: #{e.message}")
            end
          end
        end
      end
    end
  end
end
