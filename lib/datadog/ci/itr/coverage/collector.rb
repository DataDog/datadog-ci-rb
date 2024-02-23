# frozen_string_literal: true

require_relative "../../utils/git"
require_relative "../../../../ddcov/ddcov"

module Datadog
  module CI
    module Itr
      module Coverage
        class Collector
          def initialize
            # TODO: make this thread local
          end

          def setup
            p "RUNNING WITH CODE COVERAGE ENABLED"
          end

          def start
            @ddcov = DDCov.new(Utils::Git.root)
            @ddcov.start
          end

          def stop
            @ddcov.stop
            # p "RAW"
            # p result.count
          end
        end
      end
    end
  end
end
