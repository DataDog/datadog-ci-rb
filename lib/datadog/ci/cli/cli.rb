require "optparse"

module Datadog
  module CI
    module CLI
      def self.exec(action)
        case action
        when "skipped-tests", "skippable-tests"
          exec_skippable_tests_percentage
        else
          puts("Available commands:")
          puts("  skippable-tests - calculates the exact percentage of skipped tests and prints it to stdout or file")
        end
      end

      def self.exec_skippable_tests_percentage
        require "datadog/ci/test_optimisation/skippable_percentage"

        ddcirb_options = {}
        OptionParser.new do |opts|
          opts.banner = "Usage: bundle exec ddcirb skippable-tests [options]"

          opts.on("-f", "--file FILENAME", "Output result to file FILENAME")
          opts.on("--rspec-opts=[OPTIONS]", "Command line options to pass to RSpec")
        end.parse!(into: ddcirb_options)

        additional_rspec_opts = (ddcirb_options[:"rspec-opts"] || "").split

        percentage_skipped = ::Datadog::CI::TestOptimisation::SkippablePercentage.new(
          rspec_cli_options: additional_rspec_opts
        ).calculate

        if ddcirb_options[:file]
          File.write(ddcirb_options[:file], percentage_skipped)
        else
          print(percentage_skipped)
        end
      end
    end
  end
end
