# frozen_string_literal: true

module Datadog
  module CI
    module TestDiscovery
      # Null object used when test discovery component is unavailable
      class NullComponent
        def configure(_library_settings = nil, _test_session = nil)
        end

        def disable_features_for_test_discovery!(_settings = nil)
        end

        def start
        end

        def finish
        end

        def record_test(name:, suite:, module_name:, parameters:, source_file:)
        end

        def shutdown!
        end

        def enabled?
          false
        end
      end
    end
  end
end
