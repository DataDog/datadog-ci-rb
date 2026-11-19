# frozen_string_literal: true

require "msgpack"

module Datadog
  module CI
    module Utils
      module Encoding
        module MsgpackEncoder
          def self.encode(value)
            MessagePack.pack(value)
          end
        end
      end

      def self.utf8_encode(value)
        value.to_s.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
    end
  end
end
