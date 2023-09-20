# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module TestVisibility
      module Serializer
        class Span < Base
          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new
          end
        end
      end
    end
  end
end
