# frozen_string_literal: true

module Datadog
  module CI
    module TestVisibility
      class NullTransport
        def initialize
        end

        def send_traces(traces)
          []
        end
      end
    end
  end
end
