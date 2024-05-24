# frozen_string_literal: true

require "datadog/tracing/contrib/patcher"

module Datadog
  module CI
    module Contrib
      module Selenium
        # Patcher enables patching of 'Selenium::WebDriver' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Datadog.logger.info("Patch Selenium")
          end
        end
      end
    end
  end
end
