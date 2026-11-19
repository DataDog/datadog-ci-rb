# frozen_string_literal: true

module Datadog
  module CI
    module TracerBridge
      class NullComponent
        def on_session_started(_session)
        end

        def on_session_finished(_session)
        end

        def on_test_started(_test)
        end

        def on_test_finished(_test)
        end

        def on_span_started(_span)
        end

        def on_span_finished(_span)
        end

        def observe(_tracer)
        end

        def write(_trace)
          false
        end

        def shutdown!
        end
      end
    end
  end
end
