require "datadog"
require "datadog/ci"

require_relative "command/exec"
require_relative "command/skippable_tests_percentage"
require_relative "command/skippable_tests_percentage_estimate"

module Datadog
  module CI
    module CLI
      def self.exec(action, args = [])
        case action
        when "exec"
          Command::Exec.new(args).exec
        when "skipped-tests", "skippable-tests"
          Command::SkippableTestsPercentage.new.exec
        when "skipped-tests-estimate", "skippable-tests-estimate"
          Command::SkippableTestsPercentageEstimate.new.exec
        else
          puts("Usage: bundle exec ddcirb [command] [options]. Available commands:")
          puts("  skippable-tests - calculates the exact percentage of skipped tests and prints it to stdout or file")
          puts("  skippable-tests-estimate - estimates the percentage of skipped tests and prints it to stdout or file")
          puts("  exec YOUR_TEST_COMMAND - automatically instruments your test command with Datadog and executes it")
        end
      end
    end
  end
end
