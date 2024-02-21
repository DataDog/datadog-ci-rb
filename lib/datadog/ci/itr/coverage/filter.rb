# frozen_string_literal: true

require_relative "../../utils/git"

module Datadog
  module CI
    module Itr
      module Coverage
        class Filter
          def self.call(raw_result)
            new.call(raw_result)
          end

          def initialize(root: Utils::Git.root)
            @regex = /\A#{Regexp.escape(root + File::SEPARATOR)}/i.freeze
          end

          def call(raw_result)
            return nil if raw_result.nil?

            raw_result.filter_map do |path, coverage|
              next unless path =~ @regex
              next unless coverage[:lines].any? { |line| !line.nil? && line > 0 }

              [path, convert_lines_to_bitmap(coverage[:lines])]
            end
          end

          private

          def convert_lines_to_bitmap(lines)
            bitmap = []
            current = 0
            bit = 1 << 63
            lines.each do |line|
              if !line.nil? && line > 0
                current |= bit
              end
              bit >>= 1
              if bit == 0
                bitmap << current
                current = 0
                bit = 1 << 63
              end
            end
            bitmap << current
            lines
          end
        end
      end
    end
  end
end
