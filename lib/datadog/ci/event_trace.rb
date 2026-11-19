# frozen_string_literal: true

module Datadog
  module CI
    # A completed group of events with the same trace identity.
    class EventTrace
      attr_reader :id, :spans, :runtime_id
      attr_accessor :origin

      def initialize(id, spans, runtime_id:, origin: "ciapp-test")
        @id = id
        @spans = spans
        @runtime_id = runtime_id
        @origin = origin
      end
    end
  end
end
