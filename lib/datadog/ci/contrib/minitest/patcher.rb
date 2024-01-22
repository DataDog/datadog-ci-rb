# frozen_string_literal: true

require_relative "reporter"
require_relative "hooks"
require_relative "runnable"

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
            ::Minitest::CompositeReporter.include(Reporter)
            ::Minitest::Test.include(Hooks)
            ::Minitest::Runnable.include(Runnable)
          end
        end
      end
    end
  end
end
