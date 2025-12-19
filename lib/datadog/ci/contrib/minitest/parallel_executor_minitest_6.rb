# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../../utils/source_code"
require_relative "../instrumentation"
require_relative "ext"
require_relative "helpers"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Lifecycle hooks to instrument Minitest::Test
        module ParallelExecutorMinitest6
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def start
              return super unless datadog_configuration[:enabled]

              @pool = Array.new(size) {
                Thread.new @queue do |queue|
                  Thread.current.abort_on_exception = true
                  while (job = queue.pop)
                    klass, method, reporter = job
                    reporter.synchronize { reporter.prerecord klass, method }
                    result = ::Minitest.run_one_method(klass, method)
                    reporter.synchronize { reporter.record result }
                  end
                end
              }
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end
          end
        end
      end
    end
  end
end
