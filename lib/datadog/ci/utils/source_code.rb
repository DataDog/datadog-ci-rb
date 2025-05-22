# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module SourceCode
        begin
          require "datadog_source_code.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

          LAST_LINE_AVAILABLE = true
        rescue LoadError
          LAST_LINE_AVAILABLE = false
        end

        def self.last_line(target)
          return nil if target.nil?
          return nil unless LAST_LINE_AVAILABLE

          # Ruby has outdated RBS for RubyVM::InstructionSequence where method `of` is not defined
          # steep:ignore:start
          iseq = RubyVM::InstructionSequence.of(target)
          # steep:ignore:end
          _native_last_line_from_iseq(iseq)
        end
      end
    end
  end
end
