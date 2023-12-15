# frozen_string_literal: true

require_relative "hooks"
require_relative "plugin"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Patcher enables patching of 'minitest' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Minitest::Test.include(Hooks)
            ::Minitest.include(Plugin)

            ::Minitest.extensions << "datadog_ci"
          end
        end
      end
    end
  end
end
