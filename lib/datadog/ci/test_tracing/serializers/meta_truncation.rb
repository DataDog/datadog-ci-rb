# frozen_string_literal: true

module Datadog
  module CI
    module TestTracing
      module Serializers
        module MetaTruncation
          MAX_META_STRING_LENGTH = 5000

          def self.truncate_value(value)
            return value unless value.is_a?(String) && value.length > MAX_META_STRING_LENGTH

            value[0, MAX_META_STRING_LENGTH]
          end

          def self.truncate_string_values(tags)
            tags.transform_values { |value| truncate_value(value) }
          end
        end
      end
    end
  end
end
