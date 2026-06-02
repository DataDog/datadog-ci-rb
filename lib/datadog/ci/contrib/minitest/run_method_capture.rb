# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        # Captures the concrete Minitest::Test#run implementation below Datadog.
        #
        # This exists because ci-queue loads minitest-reporters, and minitest-reporters
        # aliases the current Minitest::Test#run as run_without_hooks before replacing it
        # with its own wrapper. If Datadog has already prepended its run method, that alias
        # points back to Datadog and re-enters the same active test span.
        #
        # Auto-instrumentation makes this trickier: it patches from a script_compiled
        # TracePoint, so it can observe Minitest::Test while `require "minitest"` is still
        # evaluating the class body. In that window Minitest::Test exists, but its concrete
        # #run has not been defined yet, so instance_method(:run) resolves to the abstract
        # Minitest::Runnable#run. The one-shot method_added path below replaces that early
        # abstract capture with the concrete Minitest::Test#run, before later plugin wrappers
        # like minitest-reporters can alias Datadog's wrapper.
        module RunMethodCapture
          class << self
            def capture_concrete_pre_datadog_run!(storage, owner, datadog_run_owner)
              saved_run = storage._dd_pre_datadog_minitest_run
              return if concrete_pre_datadog_run?(saved_run, datadog_run_owner)
              return if !defined?(::Minitest::Test) || !owner.equal?(::Minitest::Test)

              datadog_run = owner.instance_method(:run)
              return unless datadog_run.owner == datadog_run_owner

              candidate_run = datadog_run.super_method
              if concrete_pre_datadog_run?(candidate_run, datadog_run_owner)
                storage._dd_pre_datadog_minitest_run = candidate_run
              end
            end

            def concrete_pre_datadog_run?(method, datadog_run_owner)
              method &&
                method.owner != datadog_run_owner &&
                (!defined?(::Minitest::Runnable) || method.owner != ::Minitest::Runnable)
            end
          end
        end
      end
    end
  end
end
