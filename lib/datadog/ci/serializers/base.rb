# frozen_string_literal: true

module Datadog
  module CI
    module Serializers
      class Base
        attr_reader :trace

        def initialize(trace)
          @trace = trace
        end

        def to_json
        end

        def to_msgpack
        end
      end
    end
  end
end
