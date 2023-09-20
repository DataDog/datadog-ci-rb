# frozen_string_literal: true

module Datadog
  module CI
    module TestVisibility
      module Serializer
        class Base
          attr_reader :trace, :span

          def initialize(trace, span)
            @trace = trace
            @span = span
          end

          def runtime_id
            @trace.runtime_id
          end

          # Used for serialization
          # @return [Integer] in nanoseconds since Epoch
          def time_nano(time)
            time.to_i * 1000000000 + time.nsec
          end

          # Used for serialization
          # @return [Integer] in nanoseconds since Epoch
          def duration_nano(duration)
            (duration * 1e9).to_i
          end
        end
      end
    end
  end
end
