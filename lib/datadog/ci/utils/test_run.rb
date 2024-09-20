# frozen_string_literal: true

require "etc"

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

        def self.virtual_cpu_count
          return @virtual_cpu_count if defined?(@virtual_cpu_count)

          @virtual_cpu_count = ::Etc.nprocessors
        end
      end
    end
  end
end
