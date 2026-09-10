module Datadog
  module CI
    module CLI
      module Command
        class Exec
          def initialize(args)
            @args = args
          end

          def exec
            rubyopts = [
              "-rdatadog/ci/auto_instrument"
            ]

            existing_rubyopt = ENV["RUBYOPT"]
            ENV["RUBYOPT"] = existing_rubyopt ? "#{existing_rubyopt} #{rubyopts.join(" ")}" : rubyopts.join(" ")

            Kernel.exec(*@args)
          end
        end
      end
    end
  end
end
