require_relative "base"
require_relative "../../test_optimisation/skippable_percentage/estimator"

module Datadog
  module CI
    module CLI
      module Command
        class Exec < Base
          def initialize(args)
            super()

            @args = args
          end

          def exec
            rubyopts = [
              "-rdatadog/ci/auto_instrument"
            ]

            existing_rubyopt = ENV["RUBYOPT"] # rubocop:disable CustomCops/EnvUsageCop
            ENV["RUBYOPT"] = existing_rubyopt ? "#{existing_rubyopt} #{rubyopts.join(" ")}" : rubyopts.join(" ") # rubocop:disable CustomCops/EnvUsageCop

            Kernel.exec(*@args)
          end
        end
      end
    end
  end
end
