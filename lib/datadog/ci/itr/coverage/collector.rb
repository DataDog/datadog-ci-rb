# frozen_string_literal: true

require "coverage"

require_relative "filter"

module Datadog
  module CI
    module Itr
      module Coverage
        class Collector
          def initialize
            # Do not run code coverage if someone else is already running it.
            # It means that user is running the test with coverage and ITR would mess it up.
            @coverage_supported = !::Coverage.running?
            # @coverage_supported = false
          end

          def setup
            if @coverage_supported
              p "RUNNING WITH CODE COVERAGE ENABLED!"
              ::Coverage.setup(lines: true)
            else
              p "RUNNING WITH CODE COVERAGE DISABLED!"
            end
          end

          def start
            return unless @coverage_supported

            # if execution is threaded then coverage might already be running
            ::Coverage.resume unless ::Coverage.running?
          end

          def stop
            return nil unless @coverage_supported

            result = ::Coverage.result(stop: false, clear: true)
            ::Coverage.suspend if ::Coverage.running?

            Filter.call(result)
          end
        end
      end
    end
  end
end
