# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module TestRun
        def self.command
          return @command if defined?(@command)

          @command = "#{$0} #{ARGV.join(" ")}"
        end

        def self.skippable_test_id(test_name, suite, parameters = nil)
          "#{suite}.#{test_name}.#{parameters}"
        end

        def self.test_parameters(arguments: {}, metadata: {})
          JSON.generate(
            {
              arguments: arguments,
              metadata: metadata
            }
          )
        end
      end
    end
  end
end
