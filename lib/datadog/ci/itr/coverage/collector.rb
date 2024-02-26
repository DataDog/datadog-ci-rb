# frozen_string_literal: true

require "coverage"

require_relative "../../utils/git"
require_relative "../../../../ddcov/ddcov"

module Datadog
  module CI
    module Itr
      module Coverage
        class Collector
          def initialize(mode: :files, enabled: true)
            # TODO: make this thread local
            # modes available: :files, :lines
            @mode = mode
            @enabled = enabled

            if @enabled
              @ddcov = DDCov.new(root: Utils::Git.root, mode: mode)
            end
          end

          def setup
            if @enabled
              p "RUNNING WITH CODE COVERAGE ENABLED"
            else
              p "RUNNING WITH CODE COVERAGE DISABLED"
            end
          end

          def start
            @ddcov.start if @enabled
          end

          def stop
            @ddcov.stop if @enabled
          end
        end
      end
    end
  end
end
