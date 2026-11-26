# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Cuprite
        class ScriptExecutor
          def initialize(ferrum_browser)
            @ferrum_browser = ferrum_browser
          end

          def execute_script(script)
            @ferrum_browser.evaluate("(function() {\n#{script}\n})()")
          end
        end
      end
    end
  end
end
