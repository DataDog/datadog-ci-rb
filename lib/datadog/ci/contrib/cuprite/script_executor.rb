# frozen_string_literal: true

require_relative "../../ext/rum"

module Datadog
  module CI
    module Contrib
      module Cuprite
        class ScriptExecutor
          # Ferrum::Browser requires a JS script to be wrapped in a function() { ... } block
          WRAPPED_SCRIPTS = {
            CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE => "function() { #{CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE}; }",
            CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION => <<~JS
              function() {
                #{CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION};
              }
            JS
          }.freeze

          def initialize(ferrum_browser)
            @ferrum_browser = ferrum_browser
          end

          def execute_script(script)
            script = WRAPPED_SCRIPTS.fetch(script, script)
            @ferrum_browser.evaluate_func(script)
          end
        end
      end
    end
  end
end
