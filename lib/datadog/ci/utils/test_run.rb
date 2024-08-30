# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module TestRun
        def self.command
          return @command if defined?(@command)

          @command = "#{$0} #{ARGV.join(" ")}"
        end

        def self.datadog_test_id(test_name, suite, parameters = nil)
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

        def self.custom_configuration(env_tags)
          return {} if env_tags.nil?

          res = {}
          env_tags.each do |tag, value|
            next unless tag.start_with?("test.configuration.")

            res[tag.sub("test.configuration.", "")] = value
          end
          res
        end
      end
    end
  end
end
