# frozen_string_literal: true

require_relative "../utils/telemetry"

module Datadog
  module CI
    module Git
      module Telemetry
        def self.git_command(command)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_GIT_COMMAND, 1, tags_for_command(command))
        end

        def self.git_command_errors(command, exit_code: nil, executable_missing: false)
          tags = tags_for_command(command)

          exit_code_tag_value = exit_code_for(exit_code: exit_code, executable_missing: executable_missing)
          tags[Ext::Telemetry::TAG_EXIT_CODE] = exit_code_tag_value if exit_code_tag_value

          Utils::Telemetry.inc(Ext::Telemetry::METRIC_GIT_COMMAND_ERRORS, 1, tags)
        end

        def self.git_command_ms(command, duration_ms)
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_GIT_COMMAND_MS, duration_ms, tags_for_command(command))
        end

        def self.tags_for_command(command)
          {Ext::Telemetry::TAG_COMMAND => command}
        end

        def self.exit_code_for(exit_code: nil, executable_missing: false)
          return Ext::Telemetry::ExitCode::MISSING if executable_missing
          return exit_code.to_s if exit_code

          nil
        end
      end
    end
  end
end
