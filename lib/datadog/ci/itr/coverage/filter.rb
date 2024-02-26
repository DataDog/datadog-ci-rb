# frozen_string_literal: true

require_relative "../../utils/git"

module Datadog
  module CI
    module Itr
      module Coverage
        # not filter, but rather filter and transformer
        class Filter
          def self.call(raw_result)
            new.call(raw_result)
          end

          def initialize(root: Utils::Git.root)
            @regex = /\A#{Regexp.escape(root + File::SEPARATOR)}/i.freeze
          end

          def call(raw_result)
            return nil if raw_result.nil?

            raw_result.select do |path, coverage|
              path =~ @regex && coverage[:lines].any? { |line| !line.nil? && line > 0 }
            end
          end
        end
      end
    end
  end
end
