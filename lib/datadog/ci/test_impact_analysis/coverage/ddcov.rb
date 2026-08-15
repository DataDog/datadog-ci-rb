# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Native test-impact coverage collector.
        #
        # Only one DDCov instance may collect coverage in a process at a time.
        # Collectors may be reused or activated sequentially, but starting a
        # second collector while another one is active raises RuntimeError.
        #
        # Implementation in ext/datadog_ci_native/datadog_cov.c
        class DDCov
        end
      end
    end
  end
end
