# frozen_string_literal: true

require_relative "../patcher"

require_relative "capybara_driver"
require_relative "driver"
require_relative "navigation"

module Datadog
  module CI
    module Contrib
      module Selenium
        # Patcher enables patching of 'Selenium::WebDriver' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Selenium::WebDriver::Driver.include(Driver)
            ::Selenium::WebDriver::Navigation.include(Navigation)

            # capybara calls `reset!` after each test, so we need to patch it as well
            if defined?(::Capybara::Selenium::Driver)
              ::Capybara::Selenium::Driver.include(CapybaraDriver)
            end
          end
        end
      end
    end
  end
end
