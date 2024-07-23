# frozen_string_literal: true

require "open3"
require "pathname"

module Datadog
  module CI
    module Utils
      module Parsing
        def self.convert_to_bool(value)
          normalized_value = value.to_s.downcase
          normalized_value == "true" || normalized_value == "1"
        end
      end
    end
  end
end
