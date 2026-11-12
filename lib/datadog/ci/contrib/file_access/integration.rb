# frozen_string_literal: true

require_relative "../integration"
require_relative "patcher"

module Datadog
  module CI
    module Contrib
      module FileAccess
        class Integration < Contrib::Integration
          def available?
            true
          end

          def late_instrument?
            true
          end

          # Session-start instrumentation runs before remote configuration.
          # Leave the patcher untouched until coverage has actually been enabled.
          def patchable?
            super && Datadog.send(:components).test_impact_analysis.code_coverage?
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
