# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module TestName
        MONTH = "(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"
        WEEKDAY = "(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)"
        CONSTANT_NAME = "[A-Z]\\w*(?:::[A-Z]\\w*)*"

        DATE_INSPECT_PATTERN = /#<Date(?::[^>\n]*)?>/.freeze
        TIME_INSPECT_PATTERN = /#<(?:DateTime|Time)(?::[^>\n]*)?>/.freeze
        CLASS_INSPECT_PATTERN = /#<Class:(#{CONSTANT_NAME}|0x[0-9a-fA-F]+)(?:\s[^>\n]*)?>/.freeze
        NAMED_OBJECT_INSPECT_PATTERN = /#<(#{CONSTANT_NAME})(?::[^>\n]*)?>/.freeze
        OBJECT_INSPECT_PATTERN = /#<[^>\n]+>/.freeze

        TIME_PATTERN = /
          \b
          (?:
            \d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?
            (?:\s?(?:Z|UTC|[A-Z]{2,5}|[+-]\d{2}:?\d{2}))?
            |
            #{WEEKDAY},?\s+\d{1,2}\s+#{MONTH}\s+\d{4}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?
            (?:\s+(?:UTC|[A-Z]{2,5}|[+-]\d{2}:?\d{2}))?
          )
          \b
        /x.freeze
        DATE_PATTERN = /
          \b
          (?:
            \d{4}-\d{2}-\d{2}
            |
            #{WEEKDAY},?\s+\d{1,2}\s+#{MONTH}\s+\d{4}
          )
          \b
        /x.freeze
        RANGE_PATTERN = /
          (^|[^\w.])
          (?:-?\d+(?:\.\d+)?|DATE|TIME|:[a-zA-Z_]\w*|"[^"]*"|'[^']*')
          \s*\.{2,3}\s*
          (?:-?\d+(?:\.\d+)?|DATE|TIME|:[a-zA-Z_]\w*|"[^"]*"|'[^']*')
          (?=$|[^\w.])
        /x.freeze

        def self.normalize(name)
          return name unless name.is_a?(String)
          return name if name.empty?

          normalized = name.gsub(DATE_INSPECT_PATTERN, "DATE")
          normalized.gsub!(TIME_INSPECT_PATTERN, "TIME")
          normalized.gsub!(CLASS_INSPECT_PATTERN) do
            class_name = Regexp.last_match(1).to_s
            class_name.start_with?("0x") ? "CLASS" : "CLASS:#{class_name}"
          end
          normalized.gsub!(NAMED_OBJECT_INSPECT_PATTERN) { "OBJECT:#{Regexp.last_match(1)}" }
          normalized.gsub!(OBJECT_INSPECT_PATTERN, "OBJECT")
          normalized.gsub!(ARRAY_PATTERN) { |value| array_literal?(value) ? "ARRAY" : value }
          normalized.gsub!(HASH_PATTERN) { |value| hash_literal?(value) ? "HASH" : value }
          normalized.gsub!(TIME_PATTERN, "TIME")
          normalized.gsub!(DATE_PATTERN, "DATE")
          normalized.gsub!(RANGE_PATTERN) { "#{Regexp.last_match(1)}RANGE" }

          normalized
        rescue => e
          warn_normalization_error(e)
          name
        end

        ARRAY_PATTERN = /\[[^\[\]\n]{0,300}\]/.freeze
        HASH_PATTERN = /\{[^{}\n]{0,300}\}/.freeze

        def self.array_literal?(value)
          content = value[1, value.length - 2].to_s.strip
          return true if content.empty?

          content.include?(",") || content.match?(/\A(?:"|'|:|-?\d|true\b|false\b|nil\b|#<|\[|\{)/)
        end
        private_class_method :array_literal?

        def self.hash_literal?(value)
          content = value[1, value.length - 2].to_s.strip
          return true if content.empty?

          content.include?("=>") ||
            content.match?(/(?:\A|,)\s*(?:"[^"]+"|'[^']+'|:[a-zA-Z_]\w*|[a-zA-Z_]\w*)\s*:/)
        end
        private_class_method :hash_literal?

        def self.warn_normalization_error(error)
          Datadog.logger.warn { "Unable to normalize test name: #{error.class}: #{error.message}" }

          nil
        end
        private_class_method :warn_normalization_error
      end
    end
  end
end
