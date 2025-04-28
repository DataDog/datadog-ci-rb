# frozen_string_literal: true

module Datadog
  module CI
    module ImpactedTestsDetection
      class NullComponent
        def configure(library_settings, test_session)
        end

        def enabled?
          false
        end

        def modified?(test_span)
          false
        end

        def tag_modified_test(test_span)
        end
      end
    end
  end
end
