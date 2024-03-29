# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module TestRun
        def self.command
          return @command if defined?(@command)

          @command = "#{$0} #{ARGV.join(" ")}"
        end
      end
    end
  end
end
