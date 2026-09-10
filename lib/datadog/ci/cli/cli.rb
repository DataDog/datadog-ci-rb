require_relative "command/exec"

module Datadog
  module CI
    module CLI
      SKIPPABLE_PERCENTAGE_REMOVAL_MESSAGE =
        "Skippable percentage calculation is no longer available in ddcirb. " \
        "This functionality has moved to ddtest: https://github.com/DataDog/ddtest"

      def self.exec(action, args = [])
        case action
        when "exec"
          Command::Exec.new(args).exec
        when "skipped-tests", "skippable-tests", "skipped-tests-estimate", "skippable-tests-estimate"
          warn(SKIPPABLE_PERCENTAGE_REMOVAL_MESSAGE)
          Kernel.exit(1)
        else
          puts("Usage: bundle exec ddcirb [command] [options]. Available commands:")
          puts("  exec YOUR_TEST_COMMAND - automatically instruments your test command with Datadog and executes it")
        end
      end
    end
  end
end
