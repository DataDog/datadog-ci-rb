require "optparse"

module Datadog
  module CI
    module CLI
      module Command
        class Base
          def exec
            action = build_action
            result = action&.call

            validate!(action)
            output(result)
          end

          private

          def build_action
          end

          def options
            return @options if defined?(@options)

            ddcirb_options = {}
            OptionParser.new do |opts|
              opts.banner = "Usage: bundle exec ddcirb [command] [options]\n Available commands: skippable-tests, skippable-tests-estimate"

              opts.on("-f", "--file FILENAME", "Output result to file FILENAME")
              opts.on("--verbose", "Verbose output to stdout")

              command_options(opts)
            end.parse!(into: ddcirb_options)

            @options = ddcirb_options
          end

          def command_options(opts)
          end

          def validate!(action)
            if action.nil? || action.failed
              Datadog.logger.error("ddcirb failed, exiting")
              Kernel.exit(1)
            end
          end

          def output(result)
            if options[:file]
              File.write(options[:file], result)
            else
              print(result)
            end
          end
        end
      end
    end
  end
end
