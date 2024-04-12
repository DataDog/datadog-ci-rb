# frozen_string_literal: true

require "open3"
require "pathname"

module Datadog
  module CI
    module Utils
      module Parsing
        def self.convert_to_bool(value)
          value.to_s.downcase == "true"
        end
      end
    end
  end
end
