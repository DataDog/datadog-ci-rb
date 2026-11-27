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
        ACTIVE_RECORD_CLASS_INSPECT_PATTERN = /
          \b(#{CONSTANT_NAME})
          (?:
            \s\(call\s'\1\.connection'\sto\ establish\ a\ connection\)
            |
            \(
              (?:\.\.\.\s*)?[a-z_][a-z0-9_]*:\s[^,)\n]*
              (?:
                ,\s(?:\.\.\.\s*)?[a-z_][a-z0-9_]*:\s[^,)\n]*
              )*
            \)
          )
        /x.freeze

        TIME_PATTERN = /
          (?=[0-9MTWFS])
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
          (?=[0-9MTWFS])
          \b
          (?:
            \d{4}-\d{2}-\d{2}
            |
            #{WEEKDAY},?\s+\d{1,2}\s+#{MONTH}\s+\d{4}
          )
          \b
        /x.freeze
        RANGE_PATTERN = /
          (?=[-\dDT:"'])
          (?<![\w.])
          (?:-?\d+(?:\.\d+)?|DATE|TIME|:[a-zA-Z_]\w*|"[^"]*"|'[^']*')
          \s*\.{2,3}\s*
          (?:-?\d+(?:\.\d+)?|DATE|TIME|:[a-zA-Z_]\w*|"[^"]*"|'[^']*')
          (?![\w.])
        /x.freeze

        NEEDS_NORMALIZATION_PATTERN = /#<|[(\[{]|\.\.|\d{4}/.freeze
        FOUR_DIGITS_PATTERN = /\d{4}/.freeze
        ARRAY_LITERAL_MATCH_PATTERN = /\[(?=\s*(?:\]|[^\[\]\n]*,|(?:"|'|:|-?\d|true\b|false\b|nil\b|#<|\[|\{)))[^\[\]\n]{0,300}\]/.freeze
        HASH_LITERAL_MATCH_PATTERN = /\{(?=\s*\}|[^{}\n]*=>|(?:[^{}\n]*,)?\s*(?:"[^"}\n]+"|'[^'}\n]+'|:[a-zA-Z_]\w*|[a-zA-Z_]\w*)\s*:)[^{}\n]{0,300}\}/.freeze

        def self.normalize(name)
          return name unless name.is_a?(String)
          return name if name.empty?
          return name unless name.match?(NEEDS_NORMALIZATION_PATTERN)

          normalized = name.dup

          if normalized.include?("#<")
            normalized.gsub!(DATE_INSPECT_PATTERN, "DATE") if normalized.include?("#<Date")
            if normalized.include?("#<")
              if normalized.include?("#<DateTime") || normalized.include?("#<Time")
                normalized.gsub!(TIME_INSPECT_PATTERN, "TIME")
              end
              if normalized.include?("#<Class:")
                normalized.gsub!(CLASS_INSPECT_PATTERN) do
                  class_name = Regexp.last_match(1).to_s
                  class_name.start_with?("0x") ? "CLASS" : "CLASS:#{class_name}"
                end
              end
              if normalized.include?("#<")
                normalized.gsub!(NAMED_OBJECT_INSPECT_PATTERN, 'OBJECT:\1')
                normalized.gsub!(OBJECT_INSPECT_PATTERN, "OBJECT") if normalized.include?("#<")
              end
            end
          end

          if normalized.include?("(")
            normalized.gsub!(ACTIVE_RECORD_CLASS_INSPECT_PATTERN, '\1')
          end

          if normalized.include?("[")
            normalized.gsub!(ARRAY_LITERAL_MATCH_PATTERN, "ARRAY")
          end

          if normalized.include?("{")
            normalized.gsub!(HASH_LITERAL_MATCH_PATTERN, "HASH")
          end

          if normalized.match?(FOUR_DIGITS_PATTERN)
            if normalized.include?(":") && normalized.gsub!(TIME_PATTERN, "TIME")
              normalized.gsub!(DATE_PATTERN, "DATE") if normalized.match?(FOUR_DIGITS_PATTERN)
            else
              normalized.gsub!(DATE_PATTERN, "DATE")
            end
          end

          if normalized.include?("..")
            normalized.gsub!(RANGE_PATTERN, "RANGE")
          end

          normalized
        rescue => e
          warn_normalization_error(e)
          name
        end

        def self.warn_normalization_error(error)
          Datadog.logger.warn { "Unable to normalize test name: #{error.class}: #{error.message}" }

          nil
        end
        private_class_method :warn_normalization_error
      end
    end
  end
end
