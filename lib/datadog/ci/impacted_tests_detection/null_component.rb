# frozen_string_literal: true

module Datadog
  module CI
    module ImpactedTestsDetection
      # Null object used when impacted tests detection is unavailable
      class NullComponent
        def configure(_library_settings = nil, _test_session = nil)
        end

        def enabled?
          false
        end

        def modified?(_test_span)
          false
        end

        def tag_modified_test(_test_span)
        end
      end
    end
  end
end
