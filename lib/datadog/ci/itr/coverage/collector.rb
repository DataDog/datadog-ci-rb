# frozen_string_literal: true

require "coverage"

require_relative "filter"
require_relative "../../../../ddcov/ddcov"

module Datadog
  module CI
    module Itr
      module Coverage
        class Collector
          def initialize
            @ddcov = DDCov.new
          end

          def setup
            p "RUNNING WITH CODE COVERAGE ENABLED"
          end

          def start
            @ddcov.start
          end

          def stop
            result = @ddcov.stop
            @ddcov.instance_variable_set(:@var, {})

            Filter.call(result)
          end
        end
      end
    end
  end
end
