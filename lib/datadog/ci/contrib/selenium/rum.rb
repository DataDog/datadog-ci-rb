# frozen_string_literal: true

require_relative "ext"
require_relative "../../ext/test"
require_relative "../../utils/parsing"

module Datadog
  module CI
    module Contrib
      module Selenium
        # Provides functionality to interact with Datadog Real User Monitoring product
        # via executing JavaScript code in the browser.
        #
        # Relevant docs: https://docs.datadoghq.com/real_user_monitoring/browser/
        module RUM
          def self.is_rum_active?(script_executor)
            is_rum_active_script_result = script_executor.execute_script(Ext::SCRIPT_IS_RUM_ACTIVE)
            Datadog.logger.debug { "[Selenium] SCRIPT_IS_RUM_ACTIVE result is #{is_rum_active_script_result.inspect}" }
            Utils::Parsing.convert_to_bool(is_rum_active_script_result)
          end

          def self.stop_rum_session(script_executor)
            config = Datadog.configuration.ci[:selenium]
            if is_rum_active?(script_executor)
              Datadog::CI.active_test&.set_tag(
                CI::Ext::Test::TAG_IS_RUM_ACTIVE,
                "true"
              )

              result = script_executor.execute_script(Ext::SCRIPT_STOP_RUM_SESSION)
              Datadog.logger.debug { "[Selenium] SCRIPT_STOP_RUM_SESSION result is #{result.inspect}" }

              # introduce a delay to allow the RUM session to be stopped
              delay = config[:rum_flush_wait_millis] / 1000.0
              Datadog.logger.debug { "[Selenium] Waiting for #{delay} seconds" }
              sleep(delay)
            end
          end
        end
      end
    end
  end
end
