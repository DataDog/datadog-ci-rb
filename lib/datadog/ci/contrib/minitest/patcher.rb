# frozen_string_literal: true

require_relative "runner"
require_relative "reporter"
require_relative "test"
require_relative "runnable"

require_relative "runnable_minitest_6"
require_relative "parallel_executor_minitest_6"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Patcher enables patching of 'minitest' module.
        module Patcher
          include Datadog::CI::Contrib::Patcher

          module_function

          def patch
            # test session start
            ::Minitest.include(Runner)

            # test suites (when not executed concurrently)
            if ::Minitest::Runnable.respond_to?(:run_suite)
              ::Minitest::Runnable.include(RunnableMinitest6)
              ::Minitest::Parallel::Executor.include(ParallelExecutorMinitest6)
            else
              ::Minitest::Runnable.include(Runnable)
            end

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
