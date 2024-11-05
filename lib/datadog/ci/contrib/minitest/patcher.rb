# frozen_string_literal: true

require_relative "runner"
require_relative "reporter"
require_relative "test"
require_relative "runnable"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Patcher enables patching of 'minitest' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # test session start
            ::Minitest.include(Runner)
            # test suites (when not executed concurrently)
            ::Minitest::Runnable.include(Runnable)
            # tests; test suites (when executed concurrently)
            ::Minitest::Test.include(Test)
            # test session finish
            ::Minitest::CompositeReporter.include(Reporter)
          end
        end
      end
    end
  end
end
